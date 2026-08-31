module EventCapture
  class Normalizer
    ISO_DATE = /\A\d{4}-\d{2}-\d{2}\z/
    DATETIME = /\A(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2})/

    def self.call(...) = new(...).call

    def initialize(event, today:, genres: Genres.none)
      @event = event.is_a?(Hash) ? event : {}
      @today = today
      @genres = genres
      @raw = {}
      @issues = []
      @salvaged_time = nil
      @time_evidence = nil
    end

    def call
      date = normalized_date
      time = normalized_time
      typed_place = cited(:place)
      venue = Location.resolve_venue(typed_place)
      locality = normalized_locality(venue)

      Candidate.new(
        title: string(event["title"]),
        subtitle: cited(:subtitle),
        subtitle_evidence: string(event["subtitle_evidence"]),
        date: date,
        date_evidence: string(event["date_evidence"]),
        time: time,
        time_evidence: time_evidence,
        place: normalized_place(typed_place, venue),
        place_evidence: string(event["place_evidence"]),
        locality: locality,
        locality_evidence: string(event["locality_evidence"]),
        canton: normalized_canton(locality, venue),
        genres: normalized_genres,
        source_url: string(event["source_url"]),
        raw: raw,
        issues: issues
      )
    end

    private

    attr_reader :event, :today, :genres, :raw, :issues, :salvaged_time, :time_evidence

    def string(value) = value.to_s.strip.presence

    def reject(field, value, issue)
      raw[field.to_s] = value
      issues << issue
      nil
    end

    def cited(field)
      value = string(event[field.to_s])
      return if value.nil?
      return value if string(event["#{field}_evidence"])

      reject(field, value, :"#{field}_uncited")
    end

    def normalized_date
      value = cited(:date)
      return if value.nil?

      claimed = value

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

    def normalized_genres
      named = Array(event["genres"]).filter_map { |genre| string(genre) }
      split = named.flat_map { |genre| genres.split(genre) }
      issues << :genres_split unless split == named
      split
    end

    def normalized_time
      value, evidence = time_and_evidence
      return if value.nil?

      normalized = Clock.parse(value)
      return reject(:time, value, :time_unparseable) if normalized.nil?

      if normalized != value
        raw["time"] = value
        issues << :time_normalized
      end
      @time_evidence = evidence
      normalized
    end

    def time_and_evidence
      value = cited(:time)
      return [value, string(event["time_evidence"])] unless value.nil?
      return [nil, nil] if salvaged_time.nil?

      [salvaged_time, string(event["date_evidence"])]
    end

    def normalized_place(typed, venue)
      return typed if venue.nil? || venue.name == typed

      issues << :place_normalized
      venue.name
    end

    def normalized_locality(venue)
      typed = cited(:locality)
      town = venue&.locality.presence
      return folded_locality(typed) if town.nil?

      if typed.present? && Fingerprint.for(typed) != Fingerprint.for(town)
        raw["locality"] = typed
        issues << :locality_from_place
      end
      town
    end

    def folded_locality(typed)
      return if typed.nil?

      canonical = Locality.canonical_name(typed)
      return typed if canonical == typed

      issues << :locality_normalized
      canonical
    end

    def normalized_canton(locality, venue)
      claimed = claimed_canton
      computed = venue&.canton.presence || Locality.canton_for(locality)
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
