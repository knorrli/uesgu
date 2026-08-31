# frozen_string_literal: true

require "ipaddr"

module DatacenterNets
  LIST_PATH = Rails.root.join("config", "datacenter_nets.txt")

  MUTEX = Mutex.new
  private_constant :MUTEX

  class Table
    def initialize(ranges)
      sorted  = ranges.sort_by(&:first)
      @starts = sorted.map(&:first).freeze
      @ends   = sorted.map(&:last).freeze
    end

    def include?(int)
      index = (@starts.bsearch_index { |start| start > int } || @starts.size) - 1
      index >= 0 && int <= @ends[index]
    end

    def size
      @starts.size
    end
  end

  class << self
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

    def reload!
      MUTEX.synchronize { @tables = nil }
    end

    private

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
        (net.ipv4? ? v4 : v6) << [range.begin.to_i, range.end.to_i]
      end

      { v4: Table.new(v4), v6: Table.new(v6) }
    end
  end
end
