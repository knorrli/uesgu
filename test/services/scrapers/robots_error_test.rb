require_relative "../../db_test_helper"

# Scrapers::Agent#get splits Mechanize's two robots outcomes into three:
# allowed / disallowed / unknown. webrobots fail-closes to a synthetic
# "Disallow: /" whenever it can't FETCH robots.txt, so an unreachable one used to
# read as a ban the venue never issued.
class Scrapers::RobotsErrorTest < ActiveSupport::TestCase
  class RobotsProbe < Scrapers::Agent
    def self.url = URI.parse("https://cms.fixture.test/?rest_route=/feed")
    def self.location = "Robots Probe"
  end
  Scrapers::All.scrapers.delete("RobotsProbe") # Registerable auto-registers it

  setup do
    @probe = RobotsProbe.new
    @page = Mechanize::Page.new(
      URI(RobotsProbe.url), { "content-type" => "text/html" },
      "<html><body><p>programme</p></body></html>", 200, @probe
    )
  end

  # Keeps the real robots gate (real webrobots) and fakes only the page I/O.
  # Stubbing fetch wholesale skips the gate — the check lives INSIDE fetch — which
  # makes every assertion below pass against deliberately broken code.
  def fake_fetch
    agent = @probe.agent
    lambda do |uri, *_rest|
      uri = URI(uri.to_s)
      if agent.robots && uri.is_a?(URI::HTTP)
        agent.robots_allowed?(uri) or raise Mechanize::RobotsDisallowedError.new(uri)
      end
      @page
    end
  end

  def get_with_robots_failing(error, &block)
    @probe.agent.stub(:get_robots, ->(_uri) { raise error }) do
      @probe.agent.stub(:fetch, fake_fetch, &block)
    end
  end

  test "a 5xx on robots.txt is not a ban — the fetch proceeds" do
    boom = Mechanize::ResponseCodeError.new(
      Mechanize::File.new(URI(RobotsProbe.url), { "content-type" => "text/plain" }, "", 500)
    )

    get_with_robots_failing(boom) do
      assert_equal @page, @probe.get(RobotsProbe.url)
    end
  end

  test "a TLS failure on robots.txt is not a ban — the fetch proceeds" do
    ssl = OpenSSL::SSL::SSLError.new(
      'hostname "cms.fixture.test" does not match the server certificate'
    )

    get_with_robots_failing(ssl) do
      assert_equal @page, @probe.get(RobotsProbe.url)
    end
  end

  test "an unreachable robots.txt is recorded on the run, naming the real cause" do
    ssl = OpenSSL::SSL::SSLError.new("certificate verify failed")

    assert_nil @probe.robots_note
    get_with_robots_failing(ssl) { @probe.get(RobotsProbe.url) }

    note = @probe.robots_note
    assert_includes note, "https://cms.fixture.test/robots.txt"
    assert_includes note, "OpenSSL::SSL::SSLError"
    assert_includes note, "certificate verify failed"
  end

  test "robots.txt is not re-requested for a site already known unreachable" do
    attempts = 0
    ssl = OpenSSL::SSL::SSLError.new("certificate verify failed")

    @probe.agent.stub(:get_robots, ->(_uri) { attempts += 1; raise ssl }) do
      @probe.agent.stub(:fetch, fake_fetch) do
        3.times { @probe.get(RobotsProbe.url) }
      end
    end

    assert_equal 1, attempts, "robots.txt should be fetched once, not once per page"
  end

  test "a genuine robots.txt Disallow still raises RobotsDisallowedError" do
    @probe.agent.stub(:get_robots, "User-agent: *\nDisallow: /\n") do
      assert_raises(Mechanize::RobotsDisallowedError) { @probe.get(RobotsProbe.url) }
    end

    assert_nil @probe.robots_note, "a real ban is a ban, not an unreachable robots.txt"
  end

  # Mechanize maps a 4xx to an empty robots.txt below us (RFC 9309 §2.3.1.3), so a
  # venue that publishes none is crawled with no note. Locked so an upgrade that
  # changed it wouldn't quietly start flagging every such venue.
  test "a 404 robots.txt allows the fetch with no note" do
    @probe.agent.stub(:get_robots, "") do
      @probe.agent.stub(:fetch, fake_fetch) do
        assert_equal @page, @probe.get(RobotsProbe.url)
      end
    end

    assert_nil @probe.robots_note
  end

  # Bad Bonn opts out via respect_robots = false; the retry must restore that,
  # not clobber it back to "enforce".
  test "the robots-free retry restores the scraper's own respect_robots setting" do
    ssl = OpenSSL::SSL::SSLError.new("certificate verify failed")

    get_with_robots_failing(ssl) { @probe.get(RobotsProbe.url) }

    assert @probe.robots
  end
end
