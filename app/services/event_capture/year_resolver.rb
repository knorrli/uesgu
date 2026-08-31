module EventCapture
  module YearResolver
    WEEKDAY_TOKENS = {
      0 => %w[so sonntag sun sunday dim dimanche],
      1 => %w[mo montag mon monday lun lundi],
      2 => %w[di dienstag tue tues tuesday mar mardi],
      3 => %w[mi mittwoch wed wednesday mer mercredi],
      4 => %w[do donnerstag thu thurs thursday jeu jeudi],
      5 => %w[fr freitag fri friday ven vendredi],
      6 => %w[sa samstag sat saturday sam samedi]
    }.freeze

    MONTH_TOKENS = {
      1 => %w[januar jan janvier], 2 => %w[februar feb fevrier février fev],
      3 => %w[marz märz mar mars], 4 => %w[april apr avril],
      5 => %w[mai may], 6 => %w[juni jun juin],
      7 => %w[juli jul juillet], 8 => %w[august aug aout août],
      9 => %w[september sep sept septembre], 10 => %w[oktober okt oct octobre],
      11 => %w[november nov novembre], 12 => %w[dezember dez dec decembre décembre]
    }.freeze

    PAST_PENALTY = 3

    WEEKDAY_WINDOW = 16

    module_function

    def call(evidence, today:)
      day, month, year, = date_parts(evidence)
      return nil unless day && month
      return date_or_nil(year, month, day) if year

      [today.year - 1, today.year, today.year + 1]
        .filter_map { |y| date_or_nil(y, month, day) }
        .min_by { |d| d < today ? (today - d).to_i * PAST_PENALTY : (d - today).to_i }
    end

    def weekday_conflict?(evidence, date)
      return false if date.nil?

      day, month, _year, at = date_parts(evidence)
      return false unless day && month

      wday = weekday_before(evidence, at)
      !wday.nil? && wday != date.wday
    end

    def weekday_before(text, index)
      weekday_in(text.to_s[[index - WEEKDAY_WINDOW, 0].max...index])
    end

    def weekday_in(text)
      t = text.to_s.downcase
      WEEKDAY_TOKENS.each { |wday, tokens| return wday if tokens.any? { |token| t.match?(/\b#{token}\b/) } }
      nil
    end

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
