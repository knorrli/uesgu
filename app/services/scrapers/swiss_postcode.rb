module Scrapers
  # Best-effort Swiss PLZ (postal code) → canton code.
  #
  # OLE aggregator feeds (e.g. BeJazz) give a venue's street / PLZ / locality but
  # NO canton, yet our location hierarchy is venue > city > canton. The PLZ is the
  # only canton signal in the payload, so we derive it here. Single-venue OLE
  # sources don't need this — they carry an explicit [venue, city, canton] in
  # config — so in practice this only fires for aggregator venues, which (for the
  # feeds we ship) are Bern-region (3xxx → BE).
  #
  # Swiss postcodes are NOT a clean per-canton partition (border PLZ straddle
  # cantons, and a handful sit in the "wrong" leading-digit block), so this is a
  # pragmatic range table, deliberately CONSERVATIVE: accurate for the Bern
  # region (the audience) and the major unambiguous blocks, and it returns `nil`
  # rather than guess when a code falls in a mixed/uncertain range. Caller treats
  # nil as "no canton" (the tag is simply dropped) — derive-or-nothing, never a
  # wrong canton. Extend the table as real feeds surface gaps.
  module SwissPostcode
    # Ordered, non-overlapping ranges we're confident about. Gaps (e.g. the
    # FR/VD-mixed 1500s, the SO/BL/AG-mixed 4300–4499) are intentionally absent →
    # nil. The Bern block (3000–3899) is the one that matters most here.
    RANGES = [
      [1200..1299, 'GE'], # Genève
      [1700..1799, 'FR'], # Fribourg city region
      [1900..1999, 'VS'], # Valais (Sion / Martigny)
      [2000..2099, 'NE'], # Neuchâtel
      [2300..2399, 'NE'], # La Chaux-de-Fonds
      [2500..2549, 'BE'], # Biel/Bienne
      [2800..2899, 'JU'], # Delémont / Jura
      [3000..3899, 'BE'], # Bern region (Bern, Thun, Interlaken …)
      [3900..3999, 'VS'], # Upper Valais (Brig, Zermatt) — NOT Bern
      [4000..4099, 'BS'], # Basel-Stadt
      [4100..4199, 'BL'], # Basel-Landschaft
      [4500..4599, 'SO'], # Solothurn
      [4600..4699, 'SO'], # Olten
      [5000..5999, 'AG'], # Aargau
      [6000..6199, 'LU'], # Luzern
      [6300..6399, 'ZG'], # Zug
      [6500..6999, 'TI'], # Ticino
      [7000..7999, 'GR'], # Graubünden
      [8000..8099, 'ZH'], # Zürich city
      [8400..8499, 'ZH'], # Winterthur
      [9000..9099, 'SG']  # St. Gallen
    ].freeze

    module_function

    # The canton code for a PLZ, or nil when the code is missing, malformed, or in
    # a range we don't confidently map.
    def canton(code)
      plz = code.to_s[/\d{4}/]&.to_i
      return nil if plz.nil?

      RANGES.each { |range, canton| return canton if range.cover?(plz) }
      nil
    end
  end
end
