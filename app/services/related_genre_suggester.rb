class RelatedGenreSuggester
  MIN_WORD = 4
  MIN_CANDIDATE = 3

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

    candidates.sort_by do |candidate|
      stem = fingerprint.include?(candidate.fingerprint) ? 0 : 1
      [stem, -candidate.events_count, candidate.name.downcase]
    end.first(limit)
  end
end
