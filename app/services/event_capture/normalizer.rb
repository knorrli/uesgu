module EventCapture
  # The "code computes" half of the extraction service. Every deterministic job the
  # model was given in the bake-off it got wrong, and every one moved in here was
  # then right — see "the model transcribes, code computes" in
  # docs/user-event-capture-design.md.
  #
  # The rule is uniform: a value that fails validation is NULLED, kept under `raw`,
  # and flagged in `issues`. Never coerced into something plausible. A null gets
  # completed by a human in one tap; a malformed date silently corrupts the feed.
  class Normalizer
    ISO_DATE = /\A\d{4}-\d{2}-\d{2}\z/
    DATETIME = /\A(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2})/

    def self.call(...) = new(...).call

    def initialize(event, today:)
      @event = event.is_a?(Hash) ? event : {}
      @today = today
      @raw = {}
      @issues = []
      @salvaged_time = nil
    end

    def call
      date = normalized_date
      time = normalized_time

      Candidate.new(
        title: string(event["title"]),
        date: date,
        date_evidence: string(event["date_evidence"]),
        time: time,
        place: cited(:place),
        place_evidence: string(event["place_evidence"]),
        locality: string(event["locality"]),
        canton: normalized_canton,
        genres: Array(event["genres"]).filter_map { |genre| string(genre) },
        source_url: string(event["source_url"]),
        raw: raw,
        issues: issues
      )
    end

    private

    attr_reader :event, :today, :raw, :issues, :salvaged_time

    def string(value) = value.to_s.strip.presence

    def reject(field, value, issue)
      raw[field.to_s] = value
      issues << issue
      nil
    end

    # The evidence rule, read back the other way: a value the model could not quote
    # is self-reported invention, whatever it says. This is the fabrication detector
    # the citation requirement buys for free, and it catches invented venues on
    # images our ground truth has no opinion about.
    def cited(field)
      value = string(event[field.to_s])
      return if value.nil?
      return value if string(event["#{field}_evidence"])

      reject(field, value, :"#{field}_uncited")
    end

    def normalized_date
      value = cited(:date)
      return if value.nil?

      # "2026-08-19T19:30:00" is a right answer in a wrong shape — split it rather
      # than bin it. The time half is only a fallback for an empty `time`.
      if (match = value.match(DATETIME))
        @salvaged_time = match[2]
        issues << :date_was_datetime
        value = match[1]
      end

      date = value.match?(ISO_DATE) ? Date.parse(value) : nil
      date.nil? ? reject(:date, value, :date_not_iso) : recomputed_year(date) || date
    rescue Date::Error
      reject(:date, value, :date_not_iso)
    end

    # Prefer the year computed from the verbatim evidence over the model's own: the
    # evidence is the one thing it read correctly every time, and it still resolved
    # the year wrong in two runs of six.
    def recomputed_year(date)
      computed = YearResolver.call(event["date_evidence"], today: today)
      return if computed.nil? || computed == date

      raw["date"] = date.to_s
      issues << :year_recomputed
      computed
    end

    def normalized_time
      value = string(event["time"]) || salvaged_time
      return if value.nil?

      normalized = clock_time(value)
      return reject(:time, value, :time_unparseable) if normalized.nil?

      if normalized != value
        raw["time"] = value
        issues << :time_normalized
      end
      normalized
    end

    # Five formats came back across the bake-off runs: 20:00, 20 Uhr, 19:30h,
    # 19.30h, 20:30 Uhr.
    def clock_time(value)
      hour, minute = if (match = value.match(/\A(\d{1,2})[:.](\d{2})/))
        [match[1].to_i, match[2].to_i]
      elsif (match = value.match(/\A(\d{1,2})\s*(?:Uhr|h)\b/i)) || (match = value.match(/\A(\d{1,2})\z/))
        [match[1].to_i, 0]
      end
      return if hour.nil? || hour > 23 || minute > 59

      format("%02d:%02d", hour, minute)
    end

    def normalized_canton
      value = string(event["canton"])
      return if value.nil?
      return value.upcase if Location::CANTON_CODES.include?(value.upcase)

      reject(:canton, value, :canton_invalid)
    end
  end
end
