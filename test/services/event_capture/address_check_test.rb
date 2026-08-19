require "test_helper"

# Half the SSRF guard. The cases below are the ones that actually get exploited:
# the metadata endpoint, a hostname that resolves inward, and the two notations
# that smuggle a blocked address past a naive check.
class EventCapture::AddressCheckTest < ActiveSupport::TestCase
  def refusal_for(host, resolves_to: nil)
    return EventCapture::AddressCheck.refusal(host) if resolves_to.nil?

    Resolv.stub(:getaddresses, resolves_to) { EventCapture::AddressCheck.refusal(host) }
  end

  test "a public address is allowed" do
    assert_nil refusal_for("example.ch", resolves_to: ["93.184.216.34"])
    assert_nil refusal_for("93.184.216.34")
  end

  test "the cloud metadata endpoint is refused, however it is reached" do
    assert_match(/non-public/, refusal_for("169.254.169.254"))
    assert_match(/non-public/, refusal_for("metadata.internal", resolves_to: ["169.254.169.254"]))
  end

  test "private, loopback and CGNAT ranges are refused" do
    ["127.0.0.1", "10.1.2.3", "172.16.0.1", "192.168.1.1", "100.64.0.1", "0.0.0.0", "::1", "fd00::1", "fe80::1"]
      .each { |address| assert_match(/non-public/, refusal_for(address), address) }
  end

  # Two notations that read as public to anything matching on the string.
  test "an IPv4-mapped IPv6 address is unwrapped before matching" do
    assert_match(/non-public/, refusal_for("::ffff:127.0.0.1")) # loopback in IPv6 clothes
    assert_match(/non-public/, refusal_for("[::1]"))            # bracketed, as a URL carries it
  end

  # A host answering with one public and one private address must not be fetched:
  # which one we would have connected to is the resolver's business, not ours.
  test "every resolved address must be public, not just the first" do
    assert_match(/non-public/, refusal_for("split.example", resolves_to: ["93.184.216.34", "10.0.0.5"]))
  end

  test "a host that does not resolve, and a blank one, are refused with a reason" do
    assert_match(/does not resolve/, refusal_for("nx.example", resolves_to: []))
    assert_match(/no host/, refusal_for(nil))
  end
end
