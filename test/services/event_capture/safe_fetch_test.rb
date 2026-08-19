require "test_helper"

# The URL adapter's fetch, with the socket and robots.txt stubbed. What is pinned
# here is the order the guards run in and that they run on EVERY hop — an innocent
# public URL redirecting to the metadata endpoint is the case this exists for.
class EventCapture::SafeFetchTest < ActiveSupport::TestCase
  class FakeRobots
    def initialize(allowed: true, error: nil)
      @allowed = allowed
      @error = error
    end

    def allowed?(_uri) = @allowed
    def error(_uri) = @error
  end

  class FakeResponse
    attr_reader :code

    def initialize(code: "200", type: "text/html", location: nil, body: "<html><body>Zorpcore</body></html>")
      @code = code
      @headers = { "content-type" => type, "location" => location }
      @body = body
    end

    def [](name) = @headers[name.downcase]
    def read_body = @body.each_char.each_slice(64) { |chunk| yield chunk.join }
  end

  class FakeHTTP
    def initialize(responses) = @responses = responses
    def request(_req) = yield(@responses.shift)
  end

  # Records the hosts actually connected to, which is how "re-checked every hop"
  # is observable at all.
  def fetch(url, responses:, robots: FakeRobots.new)
    visited = []
    starter = lambda do |host, _port, **_opts, &block|
      visited << host
      block.call(FakeHTTP.new(Array(responses)))
    end

    # Hostnames resolve to one fixed public address: this suite is about the
    # guards and the hops, and a test that asks the network what example.ch is
    # would be both slow and someone else's outage.
    result = Resolv.stub(:getaddresses, ["93.184.216.34"]) do
      Net::HTTP.stub(:start, starter) { EventCapture::SafeFetch.call(url, robots: robots) }
    end
    [result, visited]
  end

  test "a page is fetched and returned with its final URL" do
    result, visited = fetch("https://example.ch/konzerte", responses: [FakeResponse.new])

    assert_predicate result, :ok?
    assert_equal "text/html", result.content_type
    assert_equal "https://example.ch/konzerte", result.url
    assert_match "Zorpcore", result.body
    assert_equal ["example.ch"], visited
  end

  test "only http(s) is fetchable" do
    ["file:///etc/passwd", "gopher://example.ch/", "data:text/html,<b>x</b>", "not a url at all"].each do |url|
      result, visited = fetch(url, responses: [FakeResponse.new])

      assert_equal :url_invalid, result.code, url
      assert_empty visited, url
    end
  end

  # The guard must fire before the socket is opened, not after.
  test "a URL resolving to a private address is refused without connecting" do
    result, visited = fetch("http://169.254.169.254/latest/meta-data/", responses: [FakeResponse.new])

    assert_equal :address_blocked, result.code
    assert_empty visited
  end

  # The one that gets missed: what the user typed is public, what it redirects to
  # is not.
  test "a redirect to a private address is caught on the hop" do
    responses = [FakeResponse.new(code: "302", location: "http://169.254.169.254/latest/meta-data/")]
    result, visited = fetch("https://example.ch/go", responses: responses)

    assert_equal :address_blocked, result.code
    assert_equal ["example.ch"], visited
  end

  test "a relative redirect is followed against the hop it came from" do
    responses = [FakeResponse.new(code: "301", location: "/programm"), FakeResponse.new]
    result, = fetch("https://example.ch/go", responses: responses)

    assert_predicate result, :ok?
    assert_equal "https://example.ch/programm", result.url
  end

  test "a redirect loop stops at the hop cap" do
    responses = Array.new(EventCapture::SafeFetch::MAX_HOPS) { FakeResponse.new(code: "302", location: "https://example.ch/again") }
    result, visited = fetch("https://example.ch/again", responses: responses)

    assert_equal :too_many_redirects, result.code
    assert_equal EventCapture::SafeFetch::MAX_HOPS, visited.size
  end

  # A refusal is not a dead end — :robots_disallowed is what tells the verify
  # screen to offer the image and text adapters instead.
  test "a genuine Disallow refuses the fetch, and says so in its own code" do
    result, visited = fetch("https://bejazz.ch/programm", responses: [FakeResponse.new],
                                                          robots: FakeRobots.new(allowed: false))

    assert_equal :robots_disallowed, result.code
    assert_empty visited
  end

  # #97: webrobots fabricates a synthetic "Disallow: /" when the robots.txt fetch
  # itself fails, so without this a contributor would be told "this site says no"
  # about a site that never said anything (Schüür 500s on /robots.txt while
  # serving its programme at 200).
  test "an unreachable robots.txt is unknown, not a ban" do
    robots = FakeRobots.new(allowed: false, error: Net::HTTPBadResponse.new("500 on /robots.txt"))
    result, visited = fetch("https://schuur.ch/programm", responses: [FakeResponse.new], robots: robots)

    assert_predicate result, :ok?
    assert_equal ["schuur.ch"], visited
  end

  test "a non-200, an unreadable type and an oversized body each fail with a reason" do
    result, = fetch("https://example.ch/x", responses: [FakeResponse.new(code: "404")])
    assert_equal :http_error, result.code

    result, = fetch("https://example.ch/x", responses: [FakeResponse.new(type: "application/pdf")])
    assert_equal :unsupported_content, result.code

    oversized = FakeResponse.new(body: "x" * (EventCapture::SafeFetch::MAX_BYTES + 128))
    result, = fetch("https://example.ch/x", responses: [oversized])
    assert_equal :too_large, result.code
  end

  test "a directly linked poster comes back as an image, not as text" do
    result, = fetch("https://example.ch/poster.jpg", responses: [FakeResponse.new(type: "image/jpeg", body: "\xFF\xD8\xFF")])

    assert_predicate result, :ok?
    assert_equal "image/jpeg", result.content_type
  end

  test "a dead host is one failed row, not an exception" do
    starter = ->(*, **, &_block) { raise SocketError, "getaddrinfo: nodename nor servname provided" }

    result = Resolv.stub(:getaddresses, ["93.184.216.34"]) do
      Net::HTTP.stub(:start, starter) { EventCapture::SafeFetch.call("https://example.ch/x", robots: FakeRobots.new) }
    end

    assert_equal :unreachable, result.code
    assert_match(/SocketError/, result.error)
  end
end
