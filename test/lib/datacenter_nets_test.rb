require "test_helper"

class DatacenterNetsTest < ActiveSupport::TestCase
  def table
    @table ||= DatacenterNets::Table.new([ [ 100, 200 ], [ 500, 600 ] ])
  end

  test "matches the first and last address of a range" do
    assert table.include?(100)
    assert table.include?(200)
    assert table.include?(500)
    assert table.include?(600)
  end

  test "misses the addresses immediately outside every range" do
    refute table.include?(99)
    refute table.include?(201)
    refute table.include?(499)
    refute table.include?(601)
  end

  test "misses an address in the gap between two ranges" do
    refute table.include?(350)
  end

  test "misses an address below the lowest range and above the highest" do
    refute table.include?(0)
    refute table.include?(10_000)
  end

  test "an empty table matches nothing" do
    assert_not DatacenterNets::Table.new([]).include?(42)
  end

  test "orders ranges itself rather than trusting the caller" do
    unsorted = DatacenterNets::Table.new([ [ 500, 600 ], [ 100, 200 ] ])

    assert unsorted.include?(150)
    assert unsorted.include?(550)
    refute unsorted.include?(300)
  end

  test "an unparseable client address is never blocked" do
    refute DatacenterNets.include?(nil)
  end

  test "resolves an IPv4-mapped IPv6 address to its IPv4 form" do
    assert DatacenterNets.include?(IPAddr.new("::ffff:47.80.0.1"))
  end

  test "matches IPv6 clients against the IPv6 table" do
    v6_cidr = list_lines.find { |line| line.include?(":") }
    first_address = IPAddr.new(v6_cidr).to_range.begin

    assert DatacenterNets.include?(first_address),
           "expected #{first_address} (from #{v6_cidr}) to be listed"
  end

  test "leaves the IPv6 documentation range alone" do
    refute DatacenterNets.include?(IPAddr.new("2001:db8::1"))
  end

  def list_lines
    @list_lines ||= DatacenterNets::LIST_PATH.readlines(chomp: true).
      reject { |line| line.strip.empty? || line.start_with?("#") }
  end

  test "the vendored list is large enough to be the real thing" do
    assert_operator DatacenterNets.v4.size, :>, 5_000
    assert_operator DatacenterNets.v6.size, :>, 1_000
  end

  test "every line of the vendored list is a parseable CIDR" do
    bad = list_lines.reject do |line|
      IPAddr.new(line)
      true
    rescue IPAddr::InvalidAddressError, ArgumentError
      false
    end

    assert_empty bad, "unparseable entries in the generated list"
  end

  test "the vendored list is disjoint and ascending within each family" do
    list_lines.group_by { |line| line.include?(":") }.each_value do |lines|
      ranges = lines.map do |line|
        net = IPAddr.new(line)
        [ net.to_range.begin.to_i, net.to_range.end.to_i, line ]
      end

      ranges.each_cons(2) do |(_, previous_end, previous_line), (start, _, line)|
        assert_operator start, :>, previous_end,
                        "#{line} overlaps or precedes #{previous_line}"
      end
    end
  end

  SAMPLES = YAML.load_file(
    Rails.root.join("test", "fixtures", "files", "datacenter_net_samples.yml")
  ).freeze

  test "every source that fed the list is actually represented in it" do
    assert_operator SAMPLES.size, :>=, 14, "expected one sample per configured source"

    SAMPLES.each do |source, address|
      assert DatacenterNets.include?(IPAddr.new(address)),
             "#{source} contributed nothing to the list (#{address} is not blocked)"
    end
  end

  test "blocks the Alibaba range the August 2026 crawl came from" do
    %w[47.74.0.1 47.79.51.85 47.82.54.165 47.87.255.254].each do |address|
      assert DatacenterNets.include?(IPAddr.new(address)), "expected #{address} to stay blocked"
    end
  end

  SERVABLE = {
    "Cloudflare resolver" => "1.1.1.1",
    "Cloudflare edge (Render's front door)" => "104.23.175.21",
    "Cloudflare edge, second range" => "162.158.111.26",
    "Google public DNS (goog, not GCP)" => "8.8.8.8",
    "Apple" => "17.253.144.10",
    "Swisscom fixed" => "195.186.1.1",
    "Swisscom fixed, second range" => "83.76.0.1",
    "Swisscom mobile" => "178.197.0.1",
    "Sunrise" => "84.75.0.1",
    "Salt" => "92.106.0.1",
    "Init7" => "77.109.128.1",
    "Quickline" => "178.196.0.1",
    "TEST-NET-2, used across this suite" => "198.51.100.9",
    "TEST-NET-3, used across this suite" => "203.0.113.7"
  }.freeze

  test "never blocks a consumer ISP, a CDN egress pool, or the Cloudflare edge" do
    SERVABLE.each do |label, address|
      refute DatacenterNets.include?(IPAddr.new(address)),
             "#{label} (#{address}) must never be blocked — see issue #85"
    end
  end
end
