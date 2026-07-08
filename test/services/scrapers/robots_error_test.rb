require_relative "../../db_test_helper"

# Scrapers::Agent#get unwraps Mechanize's misleading RobotsDisallowedError.
# webrobots fail-closes to a synthetic "Disallow: /" whenever it can't FETCH
# robots.txt (a TLS/connection failure), so a wrong-host cert — the real
# Südpol cms.sudpol.ch fault — surfaced as a phantom robots ban. The override
# re-raises the swallowed fetch error so the run reports the true cause, while
# leaving a genuine ban untouched.
class Scrapers::RobotsErrorTest < ActiveSupport::TestCase
  # A throwaway agent that exercises the REAL Scrapers::Agent#get (unlike the
  # counting harness, which stubs get to a no-op). Deregistered immediately so it
  # never leaks into the nightly sweep or the golden suite.
  class RobotsProbe < Scrapers::Agent
    def self.url = "https://cms.fixture.test/?rest_route=/feed"
  end
  Scrapers::All.scrapers.delete("RobotsProbe")

  test "an unfetchable robots.txt re-raises the underlying fetch error, not RobotsDisallowedError" do
    probe = RobotsProbe.new
    ssl = OpenSSL::SSL::SSLError.new(
      'hostname "cms.fixture.test" does not match the server certificate'
    )

    # Simulate the TLS failure at the robots.txt fetch: webrobots rescues it,
    # fabricates Disallow:/, and Mechanize would otherwise raise a robots ban.
    probe.agent.stub(:get_robots, ->(_uri) { raise ssl }) do
      err = assert_raises(OpenSSL::SSL::SSLError) { probe.get(RobotsProbe.url) }
      assert_equal ssl.message, err.message
    end
  end

  test "a genuine robots.txt Disallow still raises RobotsDisallowedError" do
    probe = RobotsProbe.new

    # A real ban: robots.txt fetches cleanly and forbids everything. No stashed
    # fetch error → robots_error! is a no-op → the honest ban propagates.
    probe.agent.stub(:get_robots, "User-agent: *\nDisallow: /\n") do
      assert_raises(Mechanize::RobotsDisallowedError) { probe.get(RobotsProbe.url) }
    end
  end
end
