class RelatedGenreSuggester
  # Suggest existing genres that share WORDING with a (usually novel) genre, so
  # filing "Grindpunk" surfaces "Grind" and "Punk" — the tighter parent or the
  # merge target you'd otherwise have to already know to go search for. This is
  # what turns "no idea where this goes" into a one-tap decision.
  #
  # Deliberately distinct from AliasSuggester, which is Levenshtein on the
  # fingerprint (near-spellings: "grindpunkz" → "grindpunk"). Edit distance never
  # relates "grindpunk" to "grind" (4 edits apart); this matches by fingerprint
  # CONTAINMENT instead — an existing genre sitting inside the new token, or an
  # existing genre containing one of the new name's words. Same high-precision
  # candidate set as the parent picker (real, non-alias, non-hidden/blocked
  # genres, in the tree or in use), ranked stem-first then by popularity.
  MIN_WORD = 4      # ignore stubby word fragments so "nu"/"pop" don't over-match
  MIN_CANDIDATE = 3 # and never surface a one/two-letter genre as a "relative"

  def self.call(genre, limit: 5, exclude: [])
    new(genre).call(limit:, exclude:)
  end

  def initialize(genre)
    @genre = genre
  end

  def call(limit: 5, exclude: [])
    fingerprint = @genre&.fingerprint
    return [] if fingerprint.blank?

    words = @genre.name.to_s.split(/[^[:alnum:]]+/)
                  .map { |word| Genre.fingerprint_for(word) }
                  .select { |word| word.length >= MIN_WORD }.uniq

    # OR of: (1) an existing genre's fingerprint is a substring of ours — the stem
    # match that finds "grind"/"punk" inside "grindpunk"; (2) an existing genre
    # contains one of our words — for multi-word names ("Klassik-Crossover" →
    # anything containing "klassik"/"crossover"). Everything is a bound parameter
    # (fingerprints are [a-z0-9] only, so no LIKE metacharacters leak).
    clauses = ["? LIKE '%' || genres.fingerprint || '%'"]
    binds   = [fingerprint]
    words.each do |word|
      clauses << "genres.fingerprint LIKE '%' || ? || '%'"
      binds   << word
    end

    candidates = Genre
      .where.not(id: [@genre.id, *exclude])
      .where(canonical_id: nil, hidden_at: nil, blocked_at: nil)
      .where("events_count > 0 OR parent_id IS NOT NULL")
      .where("length(genres.fingerprint) >= ?", MIN_CANDIDATE)
      .where([clauses.join(" OR "), *binds])
      .to_a

    # Stems first (an existing genre nested inside the new token is the likeliest
    # parent/merge), then most-used, then alphabetical for a stable order.
    candidates.sort_by do |candidate|
      stem = fingerprint.include?(candidate.fingerprint) ? 0 : 1
      [stem, -candidate.events_count, candidate.name.downcase]
    end.first(limit)
  end
end
