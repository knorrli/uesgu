# frozen_string_literal: true

require "ipaddr"

# "Is this client address inside a hosting/compute provider's network?"
#
# Backs the block/datacenter-nets rule in config/initializers/rack_attack.rb —
# see that file for why a network-level signal is the only thing that separated
# the August 2026 crawl from a visitor. This module is the lookup; the ranges
# themselves are generated into config/datacenter_nets.txt by
# `bin/rails datacenter_nets:refresh`.
#
# SCOPE — compute in, edge out. The list covers providers that rent *compute*
# (AWS, GCP, Azure, Hetzner, OVH, DigitalOcean, Linode, Vultr, Scaleway, Oracle,
# Contabo, Alibaba, Tencent, Huawei). It deliberately excludes CDN and consumer
# proxy egress — Cloudflare, Fastly, Akamai, Apple, Google-outside-GCP,
# Microsoft-outside-Azure — because that is where real people come from when
# something in the path proxies them:
#
#   * iCloud Private Relay exits via Cloudflare/Akamai/Fastly pools. People turn
#     it on in iCloud settings without ever thinking of it as a VPN.
#   * Chrome's Incognito IP Protection exits via Google and partner proxies —
#     which is why the GCP source is cloud.json (customer ranges) and never
#     goog.json (all of Google, proxies and service fetchers included).
#   * Cloudflare is doubly untouchable: Render fronts the app with it, so those
#     ranges are the edge every real visitor arrives over.
#
# Consumer ISPs are not a risk at all — Swisscom, Sunrise, Salt, Init7 and
# Quickline announce their own allocations from their own ASNs, and no mechanism
# hands a home line an EC2 address.
module DatacenterNets
  LIST_PATH = Rails.root.join("config", "datacenter_nets.txt")

  MUTEX = Mutex.new
  private_constant :MUTEX

  # A sorted, non-overlapping set of integer address ranges with an O(log n)
  # membership test. The generated list is ~12k CIDRs, so the linear
  # `Array#any?` that served three Alibaba entries would cost ~134µs per request;
  # this costs ~0.4µs. Two parallel arrays rather than an array of pairs keeps
  # the search allocation-free.
  class Table
    def initialize(ranges)
      sorted  = ranges.sort_by(&:first)
      @starts = sorted.map(&:first).freeze
      @ends   = sorted.map(&:last).freeze
    end

    def include?(int)
      # bsearch_index in find-minimum mode returns the first range starting
      # strictly after the address; the only range that can contain it is the one
      # immediately before that. nil means every range starts at or below it, so
      # the candidate is the last one.
      index = (@starts.bsearch_index { |start| start > int } || @starts.size) - 1
      index >= 0 && int <= @ends[index]
    end

    def size
      @starts.size
    end
  end

  class << self
    # Takes the parsed IPAddr from Rack::Attack::Request#true_ip_addr, which is
    # nil when the forwarded address was unparseable — an unknown client is never
    # blocked by this rule.
    def include?(addr)
      return false if addr.nil?

      addr = addr.native if addr.ipv4_mapped?
      (addr.ipv4? ? v4 : v6).include?(addr.to_i)
    end

    def v4
      tables.fetch(:v4)
    end

    def v6
      tables.fetch(:v6)
    end

    # Drops the parsed tables so the next lookup re-reads the file. Only used by
    # tests that swap the list out; production loads once per process.
    def reload!
      MUTEX.synchronize { @tables = nil }
    end

    private

    # Lazy rather than loaded at boot: parsing ~12k CIDRs costs ~40ms, and paying
    # it on the first request that consults the rule keeps it off the boot path of
    # a 512MB single-worker instance.
    def tables
      @tables || MUTEX.synchronize { @tables ||= build }
    end

    def build
      v4 = []
      v6 = []

      File.foreach(LIST_PATH) do |line|
        line = line.strip
        next if line.empty? || line.start_with?("#")

        net   = IPAddr.new(line)
        range = net.to_range
        # Range#begin/#end, never #first/#last — the latter would try to
        # enumerate, which on an IPv6 /32 does not finish.
        (net.ipv4? ? v4 : v6) << [range.begin.to_i, range.end.to_i]
      end

      { v4: Table.new(v4), v6: Table.new(v6) }
    end
  end
end
