require "db_test_helper"

class RateLimitingTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store.clear
  end

  teardown do
    Rack::Attack.enabled = false
    Rack::Attack.cache.store.clear
  end

  CLIENT = { "REMOTE_ADDR" => "203.0.113.7" }.freeze

  test "throttles a single IP past the per-minute limit" do
    limit = 60

    freeze_time do
      limit.times do
        get root_path, headers: CLIENT
        assert_response :success
      end

      get root_path, headers: CLIENT
      assert_response :too_many_requests
      assert_equal "60", response.headers["Retry-After"]
    end
  end

  test "does not count fingerprinted asset requests toward the limit" do
    70.times do
      get "/assets/whatever-deadbeef.css", headers: CLIENT
      assert_not_equal 429, response.status, "asset requests must never be throttled"
    end
  end

  test "never throttles the healthcheck endpoint" do
    70.times { get "/up", headers: CLIENT }
    assert_response :success
  end

  BROWSER = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
            "(KHTML, like Gecko) Chrome/126.0 Safari/537.36".freeze

  def edge_request(client_ip:, edge_ip:, ua: BROWSER)
    {
      "REMOTE_ADDR" => edge_ip,
      "HTTP_CF_CONNECTING_IP" => client_ip,
      "HTTP_USER_AGENT" => ua
    }
  end

  test "counts one client across many Cloudflare edge IPs as a single bucket" do
    freeze_time do
      12.times do |i|
        get root_path(g: [ "Rock" ]),
            headers: edge_request(client_ip: "198.51.100.9", edge_ip: "104.23.175.#{i + 1}")
        assert_response :success
      end

      get root_path(g: [ "Rock" ]),
          headers: edge_request(client_ip: "198.51.100.9", edge_ip: "162.158.111.26")
      assert_response :too_many_requests
    end
  end

  test "keeps genuinely different clients behind the same edge in separate buckets" do
    freeze_time do
      13.times do
        get root_path(g: [ "Rock" ]),
            headers: edge_request(client_ip: "198.51.100.9", edge_ip: "104.23.175.21")
      end
      assert_response :too_many_requests

      get root_path(g: [ "Rock" ]),
          headers: edge_request(client_ip: "203.0.113.55", edge_ip: "104.23.175.21")
      assert_response :success
    end
  end

  test "throttles faceted filter URLs well below the general limit" do
    freeze_time do
      12.times do
        get root_path(g: [ "Rock" ]), headers: edge_request(client_ip: "198.51.100.10", edge_ip: "104.23.175.21")
        assert_response :success
      end

      get root_path(g: [ "Rock" ]), headers: edge_request(client_ip: "198.51.100.10", edge_ip: "104.23.175.21")
      assert_response :too_many_requests
    end
  end

  test "leaves unfiltered browsing on the general limit" do
    freeze_time do
      20.times do
        get root_path, headers: edge_request(client_ip: "198.51.100.11", edge_ip: "104.23.175.21")
        assert_response :success
      end
    end
  end

  test "blocks self-identifying crawlers outright" do
    %w[GPTBot ClaudeBot AhrefsBot SemrushBot Bytespider python-requests/2.31].each do |ua|
      get root_path, headers: edge_request(client_ip: "198.51.100.12", edge_ip: "104.23.175.21", ua: ua)
      assert_response :forbidden, "expected #{ua} to be blocked"
    end
  end

  test "blocks an anonymous client crawling the facet space" do
    get root_path(g: [ "Rock" ]),
        headers: edge_request(client_ip: "198.51.100.13", edge_ip: "104.23.175.21", ua: "")
    assert_response :forbidden
  end

  test "still serves an anonymous client on a bare path" do
    get root_path, headers: edge_request(client_ip: "198.51.100.14", edge_ip: "104.23.175.21", ua: "")
    assert_response :success
  end

  test "blocks clients inside a listed datacenter range" do
    %w[47.74.0.1 47.79.51.85 47.82.54.165 47.87.255.254].each do |ip|
      get root_path, headers: edge_request(client_ip: ip, edge_ip: "104.23.175.21")
      assert_response :forbidden, "expected #{ip} to be blocked"
    end
  end

  test "serves clients on consumer ISPs and just outside a listed range" do
    %w[47.73.255.255 195.186.1.1 83.76.0.1 178.197.0.1 84.75.0.1 77.109.128.1].each do |ip|
      get root_path, headers: edge_request(client_ip: ip, edge_ip: "104.23.175.21")
      assert_response :success, "expected #{ip} to be served"
    end
  end

  test "blocks a datacenter client even when it looks like a returning visitor" do
    cookies[:_uesgu_session] = "looks-like-a-real-visitor"
    get root_path(g: [ "Rock" ]),
        headers: edge_request(client_ip: "47.82.54.165", edge_ip: "104.23.175.21")
          .merge("HTTP_REFERER" => "https://xn--sgu-goa.ch/events")

    assert_response :forbidden
  end

  test "keys the datacenter block on the true client, not the edge" do
    get root_path, headers: edge_request(client_ip: "85.195.234.25", edge_ip: "104.23.175.21")
    assert_response :success

    get root_path, headers: edge_request(client_ip: "47.82.54.165", edge_ip: "104.23.175.21")
    assert_response :forbidden
  end

  test "handles an IPv6 client without erroring or blocking" do
    get root_path, headers: edge_request(client_ip: "2001:db8::1", edge_ip: "104.23.175.21")
    assert_response :success
  end

  test "handles an unparseable forwarded client address" do
    get root_path, headers: edge_request(client_ip: "not-an-ip-address", edge_ip: "104.23.175.21")
    assert_response :success
  end

  test "never network-blocks the subscribable calendar feed" do
    %w[47.82.54.165 3.5.0.1 13.64.0.1].each do |ip|
      get "/calendar/nonexistent-token.ics",
          headers: edge_request(client_ip: ip, edge_ip: "104.23.175.21", ua: "Google-Calendar-Importer")
      assert_not_equal 403, response.status,
                       "a calendar poll from #{ip} must not be blocked — it breaks silently"
    end
  end

  test "still blocks a datacenter client on ordinary paths while the feed is exempt" do
    get root_path, headers: edge_request(client_ip: "47.82.54.165", edge_ip: "104.23.175.21")
    assert_response :forbidden
  end

  test "tells a network-blocked client it was blocked, and which address to quote" do
    get root_path, headers: edge_request(client_ip: "47.82.54.165", edge_ip: "104.23.175.21")

    assert_response :forbidden
    assert_match(/Blocked/i, response.body)
    assert_match(/47\.82\.54\.165/, response.body, "the user needs an address to quote")
    assert_equal "text/plain", response.media_type
  end

  test "puts no contact address in the blocked response" do
    get root_path, headers: edge_request(client_ip: "47.82.54.165", edge_ip: "104.23.175.21")

    assert_no_match(/@/, response.body)
    assert_no_match(/mailto|http/i, response.body)
  end

  test "echoes the parsed address rather than the raw forwarded header" do
    get root_path, headers: {
      "REMOTE_ADDR" => "104.23.175.21",
      "HTTP_X_FORWARDED_FOR" => "47.82.54.165, <script>alert(1)</script>",
      "HTTP_USER_AGENT" => BROWSER
    }

    assert_response :forbidden
    assert_no_match(/script/, response.body)
  end

  test "keeps the other blocklists on a bare Forbidden" do
    get root_path, headers: edge_request(client_ip: "198.51.100.30", edge_ip: "104.23.175.21", ua: "GPTBot")

    assert_response :forbidden
    assert_equal "Forbidden\n", response.body
  end

  def with_allowed_ips(*cidrs)
    original = Rack::Attack::ALLOWED_IPS
    Rack::Attack.send(:remove_const, :ALLOWED_IPS)
    Rack::Attack.const_set(:ALLOWED_IPS, cidrs.map { |cidr| IPAddr.new(cidr) }.freeze)
    yield
  ensure
    Rack::Attack.send(:remove_const, :ALLOWED_IPS)
    Rack::Attack.const_set(:ALLOWED_IPS, original)
  end

  test "lets an allowlisted address through a network block" do
    with_allowed_ips("47.82.54.165") do
      get root_path, headers: edge_request(client_ip: "47.82.54.165", edge_ip: "104.23.175.21")
      assert_response :success
    end
  end

  test "accepts a CIDR in the allowlist, not just a single address" do
    with_allowed_ips("47.82.0.0/16") do
      get root_path, headers: edge_request(client_ip: "47.82.54.165", edge_ip: "104.23.175.21")
      assert_response :success
    end
  end

  test "keeps blocking everything the allowlist does not name" do
    with_allowed_ips("47.82.54.165") do
      get root_path, headers: edge_request(client_ip: "47.74.0.1", edge_ip: "104.23.175.21")
      assert_response :forbidden
    end
  end

  def with_probe_enabled
    ENV["PROBE_REQUESTS"] = "1"
    yield
  ensure
    ENV.delete("PROBE_REQUESTS")
  end

  def capture_rails_log
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end

  test "the probe observes faceted requests without blocking them" do
    log = nil
    with_probe_enabled do
      log = capture_rails_log do
        get root_path(g: [ "Rock" ]),
            headers: edge_request(client_ip: "198.51.100.20", edge_ip: "104.23.175.21")
      end
    end

    assert_response :success
    assert_match(/\[probe\]/, log)
    assert_match(/session=0/, log)
    assert_match(/ip=198\.51\.100\.20/, log)
    assert_match(/edge=104\.23\.175\.21/, log)
  end

  test "the probe stays silent unless PROBE_REQUESTS is set" do
    log = capture_rails_log do
      get root_path(g: [ "Rock" ]),
          headers: edge_request(client_ip: "198.51.100.21", edge_ip: "104.23.175.21")
    end

    assert_response :success
    assert_no_match(/\[probe\]/, log)
  end

  test "the probe records cookie PRESENCE and never cookie values" do
    secret = "s3cret-session-value-that-must-never-be-logged"
    log = nil
    with_probe_enabled do
      cookies[:_uesgu_session] = secret
      log = capture_rails_log do
        get root_path(g: [ "Rock" ]),
            headers: edge_request(client_ip: "198.51.100.22", edge_ip: "104.23.175.21")
      end
    end

    assert_match(/session=1/, log, "cookie presence must be recorded")
    assert_no_match(/#{Regexp.escape(secret)}/, log, "cookie VALUES must never reach the logs")
  end

  test "the probe reduces the referer to its host" do
    log = nil
    with_probe_enabled do
      log = capture_rails_log do
        get root_path(g: [ "Rock" ]),
            headers: edge_request(client_ip: "198.51.100.23", edge_ip: "104.23.175.21")
              .merge("HTTP_REFERER" => "https://xn--sgu-goa.ch/events?q%5B%5D=something-private")
      end
    end

    assert_match(/ref=xn--sgu-goa\.ch/, log)
    assert_no_match(/something-private/, log, "referer paths/queries must not be logged")
  end

  test "never UA-blocks the subscribable calendar feed" do
    get "/calendar/nonexistent-token.ics",
        headers: edge_request(client_ip: "198.51.100.15", edge_ip: "104.23.175.21", ua: "Google-Calendar-Importer")
    assert_not_equal 403, response.status
  end
end
