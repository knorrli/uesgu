class AliasSuggester
  MAX_DISTANCE = 2
  SHORT_FINGERPRINT = 6

  def self.call(genre, limit: 3)
    new(genre).call(limit: limit)
  end

  def initialize(genre)
    @genre = genre
  end

  def call(limit: 3)
    return [] if @genre.blank? || @genre.fingerprint.blank?

    bound = @genre.fingerprint.length < SHORT_FINGERPRINT ? 1 : MAX_DISTANCE
    distance = Genre.sanitize_sql_array(["levenshtein(genres.fingerprint, ?)", @genre.fingerprint])
    Genre
      .where.not(id: @genre.id)
      .where(canonical_id: nil, hidden_at: nil, blocked_at: nil)
      .where("events_count > 0 OR parent_id IS NOT NULL")
      .select("genres.*, #{distance} AS distance")
      .where("#{distance} <= ?", bound)
      .order("distance ASC, events_count DESC, name ASC")
      .limit(limit)
  end
end
