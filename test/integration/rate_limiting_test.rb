require "db_test_helper"

# Rack::Attack is disabled in the test env by default (so other tests can hammer
# the app freely). These tests opt it in for the duration of each example and
# clear the counter store so runs don't bleed into each other.
class RateLimitingTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store.clear
  end

  teardown do
    Rack::Attack.enabled = false
    Rack::Attack.cache.store.clear
  end

  # A public IP — the localhost safelist exempts 127.0.0.1, which is where
  # integration requests originate by default.
  CLIENT = { "REMOTE_ADDR" => "203.0.113.7" }.freeze

  test "throttles a single IP past the per-minute limit" do
    limit = 60

    # Rack::Attack counts within fixed, clock-aligned period buckets
    # (floor(now / period)). Freeze time so all limit+1 requests fall in ONE
    # bucket — otherwise a burst that straddles a minute boundary resets the
    # counter mid-run and the (limit+1)th request isn't throttled (flaky 200).
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
    # Well past the limit, but asset paths are skipped — none should be throttled.
    70.times do
      get "/assets/whatever-deadbeef.css", headers: CLIENT
      assert_not_equal 429, response.status, "asset requests must never be throttled"
    end
  end

  test "never throttles the healthcheck endpoint" do
    70.times { get "/up", headers: CLIENT }
    assert_response :success
  end

  # A plausible desktop browser UA — faceted requests need one, or they trip the
  # blank-UA blocklist below and 403 before any throttle is consulted.
  BROWSER = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
            "(KHTML, like Gecko) Chrome/126.0 Safari/537.36".freeze

  # Render fronts the app with a Cloudflare edge, so REMOTE_ADDR is an edge address
  # and the real client arrives in CF-Connecting-IP.
  def edge_request(client_ip:, edge_ip:, ua: BROWSER)
    {
      "REMOTE_ADDR" => edge_ip,
      "HTTP_CF_CONNECTING_IP" => client_ip,
      "HTTP_USER_AGENT" => ua
    }
  end

  # THE regression test for the August 2026 bandwidth incident. One crawler reached
  # the app over 12 distinct Cloudflare edge IPs in 41 seconds; because the throttle
  # keyed on REMOTE_ADDR (always an edge address) each key saw a trickle and the
  # limit never fired. Same client, many edges ⇒ ONE bucket.
  test "counts one client across many Cloudflare edge IPs as a single bucket" do
    freeze_time do
      12.times do |i|
        get root_path(g: [ "Rock" ]),
            headers: edge_request(client_ip: "198.51.100.9", edge_ip: "104.23.175.#{i + 1}")
        assert_response :success
      end

      # A 13th request from a 13th edge IP — still the same true client.
      get root_path(g: [ "Rock" ]),
          headers: edge_request(client_ip: "198.51.100.9", edge_ip: "162.158.111.26")
      assert_response :too_many_requests
    end
  end

  test "keeps genuinely different clients behind the same edge in separate buckets" do
    freeze_time do
      # Exhaust this client's faceted budget (12 allowed, the 13th trips it).
      13.times do
        get root_path(g: [ "Rock" ]),
            headers: edge_request(client_ip: "198.51.100.9", edge_ip: "104.23.175.21")
      end
      assert_response :too_many_requests

      # A different visitor that happens to share one Cloudflare edge must not
      # inherit the first one's exhausted budget.
      get root_path(g: [ "Rock" ]),
          headers: edge_request(client_ip: "203.0.113.55", edge_ip: "104.23.175.21")
      assert_response :success
    end
  end

  # The combinatorial filter space is the expensive surface (a full render behind
  # ~30 queries), so it gets a much tighter cap than the general 60/min.
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
      # Comfortably past the faceted cap of 12 — a bare path is not faceted.
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
    # A UA-less curl of the homepage is not a crawl — only the facet space is gated.
    get root_path, headers: edge_request(client_ip: "198.51.100.14", edge_ip: "104.23.175.21", ua: "")
    assert_response :success
  end

  # The list itself (boundaries, per-provider coverage, and the consumer ISPs it
  # must never contain) is tested in test/lib/datacenter_nets_test.rb. These cover
  # the wiring: that the rule consults it, on the right address, for the right
  # requests.

  # One address from each CIDR of the Alibaba allocation the Aug 2026 crawl came from.
  test "blocks clients inside a listed datacenter range" do
    %w[47.74.0.1 47.79.51.85 47.82.54.165 47.87.255.254].each do |ip|
      get root_path, headers: edge_request(client_ip: ip, edge_ip: "104.23.175.21")
      assert_response :forbidden, "expected #{ip} to be blocked"
    end
  end

  # Swiss consumer ISPs — the actual user base. 47.73.255.255 sits immediately below
  # the Alibaba allocation and is nobody's datacenter.
  test "serves clients on consumer ISPs and just outside a listed range" do
    %w[47.73.255.255 195.186.1.1 83.76.0.1 178.197.0.1 84.75.0.1 77.109.128.1].each do |ip|
      get root_path, headers: edge_request(client_ip: ip, edge_ip: "104.23.175.21")
      assert_response :success, "expected #{ip} to be served"
    end
  end

  # The measured crawl carried a session cookie on 100% of requests and a plausible
  # same-origin referer on 43% — the two signals that would normally read as "human".
  # The network block must not care about either.
  test "blocks a datacenter client even when it looks like a returning visitor" do
    cookies[:_uesgu_session] = "looks-like-a-real-visitor"
    get root_path(g: [ "Rock" ]),
        headers: edge_request(client_ip: "47.82.54.165", edge_ip: "104.23.175.21")
          .merge("HTTP_REFERER" => "https://xn--sgu-goa.ch/events")

    assert_response :forbidden
  end

  # The rule keys on the resolved client, never the edge. A Cloudflare edge address
  # is not in these ranges, so this only ever fires on a real datacenter client.
  test "keys the datacenter block on the true client, not the edge" do
    # Real client outside the range, arriving over an edge — must be served.
    get root_path, headers: edge_request(client_ip: "85.195.234.25", edge_ip: "104.23.175.21")
    assert_response :success

    # Real client inside the range, arriving over that same edge — must be blocked.
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

  # THE reason the datacenter list can be this broad. /calendar/:token is polled by
  # Google, Apple and Microsoft SERVERS on a subscriber's behalf, from precisely the
  # ranges this rule blocks. A 403 here doesn't surface as an error to the person who
  # subscribed — their calendar just quietly stops updating, so nobody finds out.
  test "never network-blocks the subscribable calendar feed" do
    %w[47.82.54.165 3.5.0.1 13.64.0.1].each do |ip|
      get "/calendar/nonexistent-token.ics",
          headers: edge_request(client_ip: ip, edge_ip: "104.23.175.21", ua: "Google-Calendar-Importer")
      assert_not_equal 403, response.status,
                       "a calendar poll from #{ip} must not be blocked — it breaks silently"
    end
  end

  test "still blocks a datacenter client on ordinary paths while the feed is exempt" do
    # The exemption is scoped to the feed, not granted to the client.
    get root_path, headers: edge_request(client_ip: "47.82.54.165", edge_ip: "104.23.175.21")
    assert_response :forbidden
  end

  test "tells a network-blocked client it was blocked, and which address to quote" do
    # A bare "Forbidden" is indistinguishable from an outage, so a false positive
    # would be read as "üsgu is down" and never reported.
    get root_path, headers: edge_request(client_ip: "47.82.54.165", edge_ip: "104.23.175.21")

    assert_response :forbidden
    assert_match(/Blocked/i, response.body)
    assert_match(/47\.82\.54\.165/, response.body, "the user needs an address to quote")
    assert_equal "text/plain", response.media_type
  end

  test "puts no contact address in the blocked response" do
    # This body is served to every blocked crawler, and 403s are what address
    # harvesters chew through. Diagnosability, never an inbox.
    get root_path, headers: edge_request(client_ip: "47.82.54.165", edge_ip: "104.23.175.21")

    assert_no_match(/@/, response.body)
    assert_no_match(/mailto|http/i, response.body)
  end

  test "echoes the parsed address rather than the raw forwarded header" do
    # true_ip falls back to X-Forwarded-For, which is attacker-controlled. Only a
    # value that survived IPAddr parsing may reach the response body.
    get root_path, headers: {
      "REMOTE_ADDR" => "104.23.175.21",
      "HTTP_X_FORWARDED_FOR" => "47.82.54.165, <script>alert(1)</script>",
      "HTTP_USER_AGENT" => BROWSER
    }

    assert_response :forbidden
    assert_no_match(/script/, response.body)
  end

  test "keeps the other blocklists on a bare Forbidden" do
    # Nothing that hints at what to change to get through.
    get root_path, headers: edge_request(client_ip: "198.51.100.30", edge_ip: "104.23.175.21", ua: "GPTBot")

    assert_response :forbidden
    assert_equal "Forbidden\n", response.body
  end

  # ALLOWED_IPS is parsed from DATACENTER_ALLOW_IPS once at boot, so exercising the
  # safelist means swapping the constant rather than the env var.
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
    # The escape hatch for a false positive: an env-var flip on Render, no deploy.
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

    # The whole point of track() over throttle(): it must never change the response.
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
    # A session cookie in a log line is a hijackable credential for anyone who can
    # read logs. Presence is all the diagnostic needs; the value must never appear.
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
    # Real calendar clients poll on a schedule with bot-shaped or absent UAs; a 403
    # here would silently break every subscription.
    get "/calendar/nonexistent-token.ics",
        headers: edge_request(client_ip: "198.51.100.15", edge_ip: "104.23.175.21", ua: "Google-Calendar-Importer")
    assert_not_equal 403, response.status
  end
end
