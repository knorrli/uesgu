class PlaceSuggester
  Suggestion = Struct.new(:name, :locality, :canton, :source, :score, keyword_init: true) do
    def registry? = source == "registry"
  end

  THRESHOLD = 0.4
  LIMIT = 5

  class << self
    def for_name(name, url: nil, limit: LIMIT)
      venue = registry_venue_for(url)
      return [suggestion(venue.name, venue.locality, venue.canton, "registry", 1.0)] if venue

      score(name, name_candidates, limit: limit)
    end

    def by_name
      rows = Place.canonicals.pluck(:name, :locality, :canton)
      rows += Venue.in_taxonomy.map { |venue| [venue.name, venue.locality, venue.canton] }
      rows.to_h { |name, locality, canton| [name, [locality, canton]] }
    end

    private

    def registry_venue_for(url)
      host = URI.parse(url.to_s.strip).host&.downcase&.delete_prefix("www.")
      return if host.blank?

      Venue.in_taxonomy.find { |venue| host == venue.domain || host.end_with?(".#{venue.domain}") }
    rescue URI::InvalidURIError
      nil
    end

    def score(name, candidates, limit:)
      folded = Fingerprint.folded(name)
      return [] if folded.blank?

      binds = [folded, folded, *candidates.binds, folded, folded, THRESHOLD]
      rows = ActiveRecord::Base.connection.select_all(sanitize([<<~SQL, *binds]))
        SELECT candidates.name, candidates.locality, candidates.canton, candidates.source,
               #{MEASURE} AS score
        FROM (#{candidates.sql}) AS candidates(name, locality, canton, folded, source)
        WHERE #{MEASURE} >= ?
        ORDER BY score DESC, candidates.name ASC
      SQL

      rows.map { |r| suggestion(r["name"], r["locality"], r["canton"], r["source"], r["score"]) }
          .uniq { |s| Fingerprint.folded(s.name) }
          .take(limit)
    end

    MEASURE = "GREATEST(strict_word_similarity(?, candidates.folded), " \
              "strict_word_similarity(candidates.folded, ?))".freeze

    Candidates = Data.define(:sql, :binds)

    PLACE_COLUMNS = "name, locality, canton, name_folded, 'place'".freeze

    def name_candidates
      registry(Venue.in_taxonomy) { |venue| [venue.name, venue.locality, venue.canton, venue.name] }
        .then { |rows| union(Place.canonicals.select(PLACE_COLUMNS).to_sql, rows) }
    end

    def registry(venues)
      venues.map do |venue|
        name, locality, canton, folded_from = yield(venue)
        [name, locality, canton, Fingerprint.folded(folded_from)]
      end
    end

    def union(places_sql, rows)
      return Candidates.new(sql: places_sql, binds: []) if rows.empty?

      values = Array.new(rows.size, "(?, ?, ?, ?, 'registry')").join(", ")
      Candidates.new(sql: "#{places_sql} UNION ALL VALUES #{values}", binds: rows.flatten)
    end

    def suggestion(name, locality, canton, source, score)
      Suggestion.new(name: name, locality: locality, canton: canton, source: source,
                     score: score.to_f.round(3))
    end

    def sanitize(array) = ActiveRecord::Base.sanitize_sql_array(array)
  end
end
