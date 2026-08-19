# Match-at-entry for a PLACE NAME: the candidates a contributor taps instead of
# minting a new one.
#
# Deliberately not used for locality. Trigrams are weak on names that short — a
# plain transposition, Luzren -> Luzern, scores 0.27, and no measure reaches
# Freiburg -> Fribourg — so that field is served by an exact fold-match in
# EventCapture::Creator plus a datalist, and its remaining variants need a curated
# alias list rather than a similarity score.
# The stake is not tidiness — nomination into /admin/venue_leads fires at
# events_count >= 2 on a Place, so three captures split across "Quartierfest" /
# "Quarterfest" / "Marzili Quartierfest" never reach the threshold and a real venue
# stays invisible forever. That is the one failure mode with no self-correcting
# path; the fingerprint is the safety net, this is the defence.
#
# Candidates span BOTH sources — captured places and the venue registry — because
# the most valuable outcome is "this is actually Dachstock": tag the event, create
# no Place at all. The registry side has no table, so it is passed in as a VALUES
# list and scored by the same SQL, rather than growing a second implementation that
# quietly disagrees at the threshold. See docs/user-event-capture-design.md
# "Matching at entry".
class PlaceSuggester
  Suggestion = Struct.new(:name, :locality, :canton, :source, :score, keyword_init: true) do
    # A registry hit means tag the event and write no Place row.
    def registry? = source == "registry"
  end

  # Fitted against the sample set: every real pair scores >= 0.58 ("Dachstok" ->
  # Dachstock) and every unrelated one <= 0.33 ("Bern" -> Wabern), so 0.4 sits in
  # the gap rather than on a slope. A suggestion never auto-applies, so erring low
  # costs one row to ignore.
  THRESHOLD = 0.4
  LIMIT = 5

  class << self
    # url is the venue's own link when the capture carried one; it short-circuits
    # the similarity measure entirely.
    def for_name(name, url: nil, limit: LIMIT)
      venue = registry_venue_for(url)
      return [suggestion(venue.name, venue.locality, venue.canton, "registry", 1.0)] if venue

      score(name, name_candidates, limit: limit)
    end

    private

    # The registry is keyed by domain, so a capture carrying zar.ch resolves to the
    # ZAR row exactly — even when the poster spells the name "Z.A.R." and no
    # similarity measure would reach it.
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

      # ONE sanitize pass over the whole statement, with every value bound rather
      # than inlined. The earlier shape built the VALUES rows through their own
      # sanitize call and then passed the result through a second one, so a '?' in a
      # registry venue name arrived at the outer pass looking like a bind placeholder
      # and raised PreparedStatementInvalid.
      binds = [folded, folded, *candidates.binds, folded, folded, THRESHOLD]
      rows = ActiveRecord::Base.connection.select_all(sanitize([<<~SQL, *binds]))
        SELECT candidates.name, candidates.locality, candidates.canton, candidates.source,
               #{MEASURE} AS score
        FROM (#{candidates.sql}) AS candidates(name, locality, canton, folded, source)
        WHERE #{MEASURE} >= ?
        ORDER BY score DESC, candidates.name ASC
      SQL

      # Deduped and truncated in Ruby, not SQL: both candidate sets are tens of rows
      # (39 registry venues), and a locality reached from both sources would
      # otherwise fill the list with one repeated name.
      rows.map { |r| suggestion(r["name"], r["locality"], r["canton"], r["source"], r["score"]) }
          .uniq { |s| Fingerprint.folded(s.name) }
          .take(limit)
    end

    # strict_word_similarity, not word_similarity: the strict form anchors the match
    # to word boundaries, which is exactly the property being bought here. Both keep
    # the deciding subset case at 1.0 ("Quartierfest" inside "Marzili Quartierfest"),
    # but the loose form also scores "Bern" against "Wabern" at 0.6 — a substring
    # that is not a word, and precisely how a locality field fills with noise.
    #
    # Symmetric because a split name shows up in both orders depending on which
    # spelling was captured first: strict_word_similarity(a, b) reaches 1.0 only
    # when a sits inside b, so scoring one direction would catch half the cases.
    MEASURE = "GREATEST(strict_word_similarity(?, candidates.folded), " \
              "strict_word_similarity(candidates.folded, ?))".freeze

    Candidates = Data.define(:sql, :binds)

    # Aliases are excluded rather than resolved: their canonical is already in the
    # set and scores at least as well, so offering the merged-away spelling would
    # only invite re-minting it.
    def name_candidates
      registry(Venue.in_taxonomy) { |venue| [venue.name, venue.locality, venue.canton, venue.name] }
        .then { |rows| union("SELECT name, locality, canton, name_folded, 'place' FROM places WHERE canonical_id IS NULL", rows) }
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
