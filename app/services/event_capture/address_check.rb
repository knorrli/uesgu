require "resolv"
require "ipaddr"

module EventCapture
  # Half of the SSRF guard for the URL adapter: our server must not be talked into
  # fetching something only it can reach. The list below is the one in
  # docs/user-event-capture-design.md; the address that actually matters is
  # 169.254.169.254, the cloud metadata endpoint, and on Render private networking
  # also makes internal service hostnames resolve to reachable private addresses.
  #
  # EVERY resolved address must be public, not merely the first: a hostname
  # answering with both a public and a private address would otherwise pass here
  # and connect to whichever the stack picked. The other half of the guard lives in
  # SafeFetch, which re-runs this on every redirect hop.
  #
  # Deliberately NOT resolve-once-then-connect-to-the-pinned-IP. That closes a real
  # TOCTOU window (DNS rebinding between this check and the connect) and is the
  # thorough version, but it is disproportionate to an admin-gated contributor
  # list — revisit if capture is ever opened to everyone.
  module AddressCheck
    BLOCKED = [
      # RFC 1918 private, loopback, link-local (incl. the metadata endpoint),
      # "this network", CGNAT, IETF protocol assignments, TEST-NET, benchmarking,
      # multicast, reserved, broadcast.
      "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16",
      "172.16.0.0/12", "192.0.0.0/24", "192.0.2.0/24", "192.168.0.0/16",
      "198.18.0.0/15", "198.51.100.0/24", "203.0.113.0/24", "224.0.0.0/4",
      "240.0.0.0/4", "255.255.255.255/32",
      # Unspecified, loopback, unique-local, link-local, multicast, discard.
      "::/128", "::1/128", "fc00::/7", "fe80::/10", "ff00::/8", "100::/64"
    ].map { |cidr| IPAddr.new(cidr) }.freeze

    module_function

    # nil when the host is safe to fetch, otherwise the reason it isn't.
    def refusal(host)
      return "no host in the URL" if host.blank?

      addresses = resolve(host)
      return "#{host} does not resolve" if addresses.empty?

      blocked = addresses.find { |address| blocked?(address) }
      "#{host} resolves to a non-public address (#{blocked})" if blocked
    end

    # A literal IP in the URL never reaches the resolver — Resolv would happily
    # hand a dotted quad straight back, but an IPv6 literal arrives bracketed and
    # would not parse, so both literal forms are settled here instead.
    def resolve(host)
      literal = IPAddr.new(host.delete_prefix("[").delete_suffix("]"))
      [literal]
    rescue IPAddr::Error
      dns_addresses(host)
    end

    def dns_addresses(host)
      Resolv.getaddresses(host).filter_map do |address|
        IPAddr.new(address)
      rescue IPAddr::Error
        nil
      end
    end

    # ::ffff:127.0.0.1 is loopback wearing an IPv6 address; unwrap before matching
    # or every v4 rule above is one notation away from being bypassed.
    def blocked?(address)
      address = address.native if address.ipv6? && address.ipv4_mapped?
      BLOCKED.any? { |range| range.include?(address) }
    end
  end
end
