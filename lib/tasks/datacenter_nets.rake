require "ipaddr"
require "json"
require "net/http"
require "uri"

module DatacenterNetsRefresh
  SAMPLES_PATH = Rails.root.join("test", "fixtures", "files", "datacenter_net_samples.yml")

  ASNS = {
    "hetzner" => 24940,
    "ovh" => 16276,
    "digitalocean" => 14061,
    "linode" => 63949,
    "vultr" => 20473,
    "scaleway" => 12876,
    "oracle" => 31898,
    "contabo" => 51167,
    "alibaba" => 45102,
    "tencent" => 132203,
    "huawei" => 55990
  }.freeze

  AWS_EDGE_SERVICES = %w[CLOUDFRONT CLOUDFRONT_ORIGIN_FACING GLOBALACCELERATOR].freeze

  module_function

  def refresh
    sources = {}
    sources["aws"]   = aws_prefixes
    sources["gcp"]   = gcp_prefixes
    sources["azure"] = azure_prefixes
    ASNS.each { |name, asn| sources["asn:#{name}"] = asn_prefixes(name, asn) }

    empty = sources.select { |_, prefixes| prefixes.empty? }.keys
    abort "aborting: no prefixes from #{empty.join(', ')}" if empty.any?

    v4, v6 = partition_ranges(sources.values.flatten.uniq)
    cidrs4 = coalesce(v4).flat_map { |s, e| range_to_cidrs(s, e, 32, Socket::AF_INET) }
    cidrs6 = coalesce(v6).flat_map { |s, e| range_to_cidrs(s, e, 128, Socket::AF_INET6) }

    write_list(sources, cidrs4, cidrs6)
    write_samples(sources)

    DatacenterNets.reload!
    puts "\nwrote #{DatacenterNets::LIST_PATH.relative_path_from(Rails.root)} — " \
         "#{cidrs4.size} IPv4 + #{cidrs6.size} IPv6 CIDRs " \
         "(#{DatacenterNets.v4.size} + #{DatacenterNets.v6.size} ranges after merge)"
    puts "wrote #{SAMPLES_PATH.relative_path_from(Rails.root)}"
  end
  def aws_prefixes
    data = get_json("https://ip-ranges.amazonaws.com/ip-ranges.json")
    all  = data["prefixes"].map { |p| p["ip_prefix"] } +
           data["ipv6_prefixes"].map { |p| p["ipv6_prefix"] }
    edge = (data["prefixes"] + data["ipv6_prefixes"]).
      select { |p| AWS_EDGE_SERVICES.include?(p["service"]) }.
      map { |p| p["ip_prefix"] || p["ipv6_prefix"] }

    prefixes = all.uniq - edge.uniq
    report("aws", prefixes, "syncToken #{data['syncToken']}")
    prefixes
  end

  def gcp_prefixes
    data = get_json("https://www.gstatic.com/ipranges/cloud.json")
    prefixes = data["prefixes"].filter_map { |p| p["ipv4Prefix"] || p["ipv6Prefix"] }
    report("gcp", prefixes, "published #{data['creationTime']}")
    prefixes
  end

  def azure_prefixes
    page = get("https://www.microsoft.com/en-us/download/details.aspx?id=56519")
    url  = page[%r{https://download\.microsoft\.com/download/[^"]*ServiceTags_Public_\d+\.json}]
    abort "aborting: could not find the Azure Service Tags JSON link" if url.nil?

    tag = JSON.parse(get(url))["values"].find { |v| v["name"] == "AzureCloud" }
    abort "aborting: no AzureCloud service tag in #{url}" if tag.nil?

    prefixes = tag["properties"]["addressPrefixes"]
    report("azure", prefixes, File.basename(URI(url).path))
    prefixes
  end

  def asn_prefixes(name, asn)
    data = get_json("https://stat.ripe.net/data/announced-prefixes/data.json" \
                    "?resource=AS#{asn}&sourceapp=uesgu")
    prefixes = (data.dig("data", "prefixes") || []).map { |p| p["prefix"] }
    report("asn:#{name}", prefixes, "AS#{asn}")
    sleep 0.3
    prefixes
  end
  def partition_ranges(prefixes)
    v4 = []
    v6 = []
    prefixes.each do |cidr|
      net   = IPAddr.new(cidr)
      range = net.to_range
      (net.ipv4? ? v4 : v6) << [ range.begin.to_i, range.end.to_i ]
    end
    [ v4, v6 ]
  end

  def coalesce(ranges)
    merged = []
    ranges.sort_by(&:first).each do |start, finish|
      if merged.any? && start <= merged.last[1] + 1
        merged.last[1] = finish if finish > merged.last[1]
      else
        merged << [ start, finish ]
      end
    end
    merged
  end

  def range_to_cidrs(start, finish, bits, family)
    out = []
    while start <= finish
      aligned = start.zero? ? bits : Math.log2(start & -start).to_i
      span    = Math.log2(finish - start + 1).to_i
      size    = [ aligned, span, bits ].min
      out << "#{IPAddr.new(start, family)}/#{bits - size}"
      start += 1 << size
    end
    out
  end
  def write_list(sources, cidrs4, cidrs6)
    header = [
      "# Datacenter / hosting-provider networks — GENERATED FILE, DO NOT EDIT BY HAND.",
      "#",
      "# Regenerate with:  bin/rails datacenter_nets:refresh",
      "# Generated:        #{Date.current}",
      "#",
      "# Scope is compute providers only. CDN and consumer-proxy egress (Cloudflare,",
      "# Fastly, Akamai, Apple, Google-outside-GCP, Microsoft-outside-Azure) is",
      "# deliberately absent, because that is where proxied REAL USERS come from —",
      "# iCloud Private Relay and Chrome IP Protection both exit that way.",
      "# See lib/datacenter_nets.rb and issue #85 before adding a source.",
      "#",
      "# published prefixes by source:"
    ]
    sources.each { |name, prefixes| header << format("#   %-18s %6d", name, prefixes.size) }
    header << format("#   %-18s %6d", "TOTAL published", sources.values.sum(&:size))
    header << format("#   %-18s %6d", "after merge", cidrs4.size + cidrs6.size)
    header << "#"

    DatacenterNets::LIST_PATH.write("#{(header + cidrs4 + cidrs6).join("\n")}\n")
  end

  def write_samples(sources)
    FileUtils.mkdir_p(SAMPLES_PATH.dirname)
    lines = [
      "# GENERATED by `bin/rails datacenter_nets:refresh` — DO NOT EDIT BY HAND.",
      "# One address per source, taken from that source's lowest published prefix.",
      "# Proves each provider survived generation; see test/lib/datacenter_nets_test.rb.",
      ""
    ]
    sources.each do |name, prefixes|
      lowest = prefixes.map { |cidr| IPAddr.new(cidr) }.
        min_by { |net| [ net.ipv4? ? 0 : 1, net.to_i ] }
      lines << "#{name.tr(':', '_')}: #{lowest.to_range.begin}"
    end
    SAMPLES_PATH.write("#{lines.join("\n")}\n")
  end
  def report(name, prefixes, note)
    puts format("  %-18s %6d prefixes   (%s)", name, prefixes.size, note)
  end

  def get_json(url)
    JSON.parse(get(url))
  end

  def get(url, redirects: 3)
    uri = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                   open_timeout: 15, read_timeout: 60) do |http|
      http.get(uri.request_uri, "User-Agent" => "uesgu-datacenter-nets/1.0")
    end

    case response
    when Net::HTTPSuccess     then response.body
    when Net::HTTPRedirection
      abort "aborting: too many redirects fetching #{url}" if redirects.zero?
      get(response["location"], redirects: redirects - 1)
    else
      abort "aborting: #{url} returned #{response.code} #{response.message}"
    end
  end
end

namespace :datacenter_nets do
  desc "Refresh config/datacenter_nets.txt from upstream provider ranges"
  task refresh: :environment do
    DatacenterNetsRefresh.refresh
  end

  desc "Check whether an address would be blocked: datacenter_nets:check[1.2.3.4]"
  task :check, [ :ip ] => :environment do |_task, args|
    raw = args[:ip] or abort "usage: bin/rails datacenter_nets:check[1.2.3.4]"

    addr = begin
      IPAddr.new(raw)
    rescue IPAddr::InvalidAddressError, ArgumentError
      abort "not a usable address: #{raw.inspect}"
    end

    if DatacenterNets.include?(addr)
      puts "#{raw}: BLOCKED — inside a listed datacenter range"
      puts "  to let it through without a deploy, add it to DATACENTER_ALLOW_IPS on Render"
    else
      puts "#{raw}: served — not in the list"
    end
  end
end
