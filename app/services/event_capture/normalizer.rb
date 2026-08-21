module EventCapture
  # The "code computes" half of the extraction service. Every deterministic job the
  # model was given in the bake-off it got wrong, and every one moved in here was
  # then right: the model transcribes, code computes.
  #
  # The rule is uniform: a value that fails validation is NULLED, kept under `raw`,
  # and flagged in `issues`. Never coerced into something plausible. A null gets
  # completed by a human in one tap; a malformed date silently corrupts the feed.
  class Normalizer
    ISO_DATE = /\A\d{4}-\d{2}-\d{2}\z/
    DATETIME = /\A(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2})/

    def self.call(...) = new(...).call

    def initialize(event, today:, localities: Localities.none, genres: Genres.none)
      @event = event.is_a?(Hash) ? event : {}
      @today = today
      @localities = localities
      @genres = genres
      @raw = {}
      @issues = []
      @salvaged_time = nil
    end

    def call
      date = normalized_date
      time = normalized_time
      # A local rather than a second `cited(:locality)` below: the canton is computed
      # from it, and `cited` flags an issue on the way past — asking twice records it twice.
      locality = cited(:locality)

      Candidate.new(
        title: string(event["title"]),
        subtitle: cited(:subtitle),
        subtitle_evidence: string(event["subtitle_evidence"]),
        date: date,
        date_evidence: string(event["date_evidence"]),
        time: time,
        place: cited(:place),
        place_evidence: string(event["place_evidence"]),
        locality: locality,
        locality_evidence: string(event["locality_evidence"]),
        canton: normalized_canton(locality),
        genres: normalized_genres,
        source_url: string(event["source_url"]),
        raw: raw,
        issues: issues
      )
    end

    private

    attr_reader :event, :today, :localities, :genres, :raw, :issues, :salvaged_time

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

      # `raw` must show what the MODEL said, so a human on the capture screen judges
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

    # The one field where the model's answer is expanded rather than trimmed: a slash
    # run is several genres in one string, and only the taxonomy can say so (see
    # EventCapture::Genres). Nothing is refused, so nothing goes to `raw` — the flag is
    # what says the rule fired.
    def normalized_genres
      named = Array(event["genres"]).filter_map { |genre| string(genre) }
      split = named.flat_map { |genre| genres.split(genre) }
      issues << :genres_split unless split == named
      split
    end

    def normalized_time
      value = string(event["time"]) || salvaged_time
      return if value.nil?

      normalized = Clock.parse(value)
      return reject(:time, value, :time_unparseable) if normalized.nil?

      if normalized != value
        raw["time"] = value
        issues << :time_normalized
      end
      normalized
    end

    # Computed from the locality, never the model's answer, because a wrong canton
    # files the locality and its venues under a branch of the WHERE tree nobody
    # looking for the event will open. The model is still asked for one: where the
    # locality is new the computation abstains, and its guess beats leaving a human
    # to pick from 26 with no default.
    def normalized_canton(locality)
      claimed = claimed_canton
      computed = localities.canton_for(locality)
      return claimed if computed.nil?
      return computed if claimed.nil? || claimed == computed

      raw["canton"] = claimed
      issues << :canton_recomputed
      computed
    end

    def claimed_canton
      value = string(event["canton"])
      return if value.nil?
      return value.upcase if Location::CANTON_CODES.include?(value.upcase)

      reject(:canton, value, :canton_invalid)
    end
  end
end
