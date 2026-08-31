module Scrapers
  module SwissPostcode
    RANGES = [
      [1200..1299, "GE"],
      [1700..1799, "FR"],
      [1900..1999, "VS"],
      [2000..2099, "NE"],
      [2300..2399, "NE"],
      [2500..2549, "BE"],
      [2800..2899, "JU"],
      [3000..3899, "BE"],
      [3900..3999, "VS"],
      [4000..4099, "BS"],
      [4100..4199, "BL"],
      [4500..4599, "SO"],
      [4600..4699, "SO"],
      [5000..5999, "AG"],
      [6000..6199, "LU"],
      [6300..6399, "ZG"],
      [6500..6999, "TI"],
      [7000..7999, "GR"],
      [8000..8099, "ZH"],
      [8400..8499, "ZH"],
      [9000..9099, "SG"]
    ].freeze

    module_function

    def canton(code)
      plz = code.to_s[/\d{4}/]&.to_i
      return nil if plz.nil?

      RANGES.each { |range, canton| return canton if range.cover?(plz) }
      nil
    end
  end
end
