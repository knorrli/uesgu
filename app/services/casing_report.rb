# What Casing.recase would do to the corpus if it were wired in, printed so the
# changes can be read one by one. The totals say how much moves; only the listing
# says whether it moved the right way, and a wrong recase is a wrong NAME rather
# than an ugly one — so the listing is the point of this class.
class CasingReport
  SECTION_WIDTH = 14

  def self.call(io = $stdout) = new(io).call

  def initialize(io)
    @io = io
  end

  def call
    section("titles", Event.pluck(:data_source, :title))
    section("descriptions", Event.pluck(:data_source, :description))
    section("places", ungrouped(Place.pluck(:name)))
    section("localities", ungrouped(Locality.pluck(:name)))
  end

  private

  attr_reader :io

  def ungrouped(values) = values.map { |value| [nil, value] }

  def section(label, rows)
    values = rows.reject { |_, value| value.blank? }
    shouted = values.select { |_, value| Casing.shouted?(value) }
    # Shouted and left alone is the single-word rule firing, which is the half of
    # the rule that protects a name — worth its own number.
    kept, recased = shouted.partition { |_, value| Casing.recase(value) == value }

    io.puts
    io.puts "#{label.ljust(SECTION_WIDTH)} #{values.size} values   #{shouted.size} shouted   " \
            "#{kept.size} left alone (one word)   #{recased.size} would recase"
    by_source(shouted, recased)
    listing(recased)
  end

  def by_source(shouted, recased)
    groups = shouted.map(&:first).compact.uniq.sort
    return if groups.empty?

    io.puts "\n  by source"
    groups.each do |group|
      io.puts "    #{group.ljust(24)} #{count_for(shouted, group)} shouted   " \
              "#{count_for(recased, group)} would recase"
    end
  end

  def count_for(rows, group) = rows.count { |source, _| source == group }

  def listing(recased)
    return if recased.empty?

    io.puts "\n  would recase"
    recased.sort_by { |source, value| [source.to_s, value] }.each do |source, value|
      io.puts "    #{"[#{source}] " if source}#{value} → #{Casing.recase(value)}"
    end
  end
end
