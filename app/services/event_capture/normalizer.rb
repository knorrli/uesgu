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

      # `raw` must show what the MODEL said, so a human on the verify screen judges
      # its output rather than our half-transformed copy of it.
      claimed = value

      # "2026-08-19T19:30:00" is a right answer in a wrong shape — split it rather
      # than bin it. The time half is only a fallback for an empty `time`.
      if (match = value.match(DATETIME))
        @salvaged_time = match[2]
        issues << :date_was_datetime
        value = match[1]
      end

      date = value.match?(ISO_DATE) ? Date.parse(value) : nil
      return reject(:date, claimed, :date_not_iso) if date.nil?

      resolved = recomputed_year(date) || date
      issues << :date_weekday_conflict if YearResolver.weekday_conflict?(event["date_evidence"], resolved)
      resolved
    rescue Date::Error
      reject(:date, claimed, :date_not_iso)
    end

    # Prefer the year computed from the verbatim evidence over the model's own: the
    # evidence is the one thing it read correctly every time, and it still resolved
    # the year wrong in two runs of six.
    #
    # The YEAR, and nothing else. A quote can legitimately span more than this event
    # — "Fr 20. & Sa 21. Februar" on a two-night poster — and taking the resolver's
    # whole answer there turned a wrong year into a wrong show (2026-02-20 became
    # 2025-02-21). A day or month disagreement means the evidence is not describing
    # this date, so the model's value stands and the disagreement is flagged for a
    # human instead of being silently resolved.
    def recomputed_year(date)
      computed = YearResolver.call(event["date_evidence"], today: today)
      return if computed.nil? || computed == date

      unless computed.month == date.month && computed.day == date.day
        issues << :date_evidence_mismatch
        return
      end

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

    # Shape-based on purpose, NOT a list of hour words. The formats that motivated
    # this were the German ones the sample images happened to carry (20 Uhr, 19:30h,
    # 19.30h) — matching that vocabulary would bake an accident of six posters into
    # the parser, and French "20h30", English "8pm" and a bare "21" are all just as
    # likely in the long tail this feature exists to reach. So: read the leading
    # numbers, treat any trailing marker as noise, and honour only a meridiem, which
    # is the one marker that changes the value rather than decorating it.
    #
    # Strict about the leading position ("Doors 19:00" is nulled, not salvaged): the
    # model is asked for HH:MM, a null costs one tap, and a wrong time does not
    # announce itself. Every rejection lands in `issues` where it can be counted.
    CLOCK = /\A(\d{1,2})\s*(?:[:.h]\s*(\d{2}))?/i
    MERIDIEM = /(?:\d|\s)([ap])\.?m\.?/i
    # "20.08." and "20.08.2026" are dates, and CLOCK reads both as 20:08. A date
    # separator still standing after the minutes is the tell — a real time does not
    # carry one, so nulling here costs nothing and a plausible wrong time costs a lot.
    DATE_TAIL = %r{\A[./]}

    def clock_time(value)
      match = value.match(CLOCK)
      return if match.nil? || DATE_TAIL.match?(value[match.end(0)..])

      hour = meridiem_hour(match[1].to_i, value)
      minute = match[2].to_i
      return if hour > 23 || minute > 59

      format("%02d:%02d", hour, minute)
    end

    def meridiem_hour(hour, value)
      case value[MERIDIEM, 1]&.downcase
      when "p" then hour < 12 ? hour + 12 : hour
      when "a" then hour == 12 ? 0 : hour
      else hour
      end
    end

    def normalized_canton
      value = string(event["canton"])
      return if value.nil?
      return value.upcase if Location::CANTON_CODES.include?(value.upcase)

      reject(:canton, value, :canton_invalid)
    end
  end
end
