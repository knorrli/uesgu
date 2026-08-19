module EventCapture
  # Resolves a printed date ("Mi 19. August") to a real Date. The model is not
  # asked to: across the bake-off runs it transcribed that evidence correctly 6/6
  # and still resolved it to 2025 in two of them, where 19 Aug 2025 is a Tuesday.
  # It can read; it cannot reliably do calendar arithmetic.
  #
  # Tractable in code because the candidate set is tiny. Someone photographing a
  # poster is looking at something happening soon, so the year is last, this or
  # next — and a printed weekday picks exactly one of those, since a given
  # day/month lands on a given weekday only once every 5-6 years.
  module YearResolver
    WEEKDAY_TOKENS = {
      0 => %w[so son sonntag sunday dimanche dim],
      1 => %w[mo mon montag monday lundi lun],
      2 => %w[di die dienstag tuesday mardi mar],
      3 => %w[mi mit mittwoch wednesday mercredi mer],
      4 => %w[do don donnerstag thursday jeudi jeu],
      5 => %w[fr fre freitag friday vendredi ven],
      6 => %w[sa sam samstag saturday samedi]
    }.freeze

    MONTH_TOKENS = {
      1 => %w[januar jan janvier], 2 => %w[februar feb fevrier février fev],
      3 => %w[marz märz mar mars], 4 => %w[april apr avril],
      5 => %w[mai may], 6 => %w[juni jun juin],
      7 => %w[juli jul juillet], 8 => %w[august aug aout août],
      9 => %w[september sep sept septembre], 10 => %w[oktober okt oct octobre],
      11 => %w[november nov novembre], 12 => %w[dezember dez dec decembre décembre]
    }.freeze

    # A past date costs three times what the same distance in the future costs, so
    # a stale poster reads as "11 days ago" rather than rolling forward a year.
    PAST_PENALTY = 3

    # How far back to look for the weekday belonging to a date. "Donnerstag, 20.
    # August" is about the longest real prefix; further away is a different clause.
    WEEKDAY_WINDOW = 16

    module_function

    # nil when the evidence carries no legible day+month — the caller keeps the
    # model's own value in that case rather than inventing one.
    def call(evidence, today:)
      day, month, year, at = date_parts(evidence)
      return nil unless day && month
      return date_or_nil(year, month, day) if year

      wday = weekday_before(evidence, at)
      candidates = [today.year - 1, today.year, today.year + 1].filter_map { |y| date_or_nil(y, month, day) }
      matching = wday ? candidates.select { |d| d.wday == wday } : candidates
      matching = candidates if matching.empty?

      matching.min_by { |d| d < today ? (today - d).to_i * PAST_PENALTY : (d - today).to_i }
    end

    # The weekday PRINTED WITH THIS DATE, never one from elsewhere in the line.
    # Scanning the whole string let a later token win — "Sa 08.08. + So 09.08."
    # read as Sunday and landed a year out — and let ordinary prose supply one,
    # since "die" and "mit" are a German article and preposition, "so" an adverb,
    # and "mar" is both mardi and an abbreviation of März. A checksum taken from
    # the wrong word is worse than no checksum: it silently selects a wrong year.
    def weekday_before(text, index)
      weekday_in(text.to_s[[index - WEEKDAY_WINDOW, 0].max...index])
    end

    def weekday_in(text)
      t = text.to_s.downcase
      WEEKDAY_TOKENS.each { |wday, tokens| return wday if tokens.any? { |token| t.match?(/\b#{token}\b/) } }
      nil
    end

    # Returns [day, month, year, offset] — the offset is what lets the weekday be
    # read from beside the date rather than from the whole string.
    #
    # Textual months are tried first: "Mi 19. August 19.30h" must read as 19 August,
    # not as day 19 of month 30.
    def date_parts(text)
      t = text.to_s
      year = t[/\b(20\d{2})\b/, 1]&.to_i

      MONTH_TOKENS.each do |month, tokens|
        tokens.each do |token|
          if (m = t.match(/\b(\d{1,2})\s*\.?\s*#{token}\b/i))
            return [m[1].to_i, month, year, m.begin(0)]
          end
        end
      end

      # Keep looking past a pair that cannot be a date. The first one is regularly a
      # time — "Doors 19.30 Uhr, Konzert am 5.12." — and stopping there threw away
      # the date entirely, which silently skipped the year check this module exists
      # to perform.
      pos = 0
      while (m = t.match(%r{\b(\d{1,2})\s*[./]\s*(\d{1,2})\b}, pos))
        day, month = m[1].to_i, m[2].to_i
        return [day, month, year, m.begin(0)] if month.between?(1, 12) && day.between?(1, 31)

        pos = m.end(0)
      end

      [nil, nil, nil, nil]
    end

    def date_or_nil(year, month, day)
      Date.new(year, month, day)
    rescue Date::Error
      nil
    end
  end
end
