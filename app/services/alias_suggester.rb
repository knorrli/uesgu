class AliasSuggester
  include ActiveRecord::ConnectionAdapters::Quoting

  # Suggest canonical genres a (likely novel or mistyped) genre could be merged
  # into — closest first, by Levenshtein distance on the *fingerprint* (so
  # "postpunkz" finds "post-punk" despite the casing/hyphen). Mirrors
  # StyleSuggester's fuzzystrmatch approach. Deliberately high-precision: a tight,
  # length-aware distance bound (short fingerprints allow only a single edit, so
  # "party" doesn't surface "parody") and only real merge targets (mapped or
  # in-use genres that aren't themselves an alias, hidden, or blocked), since a
  # merge is a human-confirmed action, not an automatic one.
  MAX_DISTANCE = 2
  SHORT_FINGERPRINT = 6 # below this length, only allow a single-character edit

  def self.call(genre, limit: 3)
    new(genre).call(limit: limit)
  end

  def initialize(genre)
    @genre = genre
  end

  def call(limit: 3)
    return [] if @genre.blank? || @genre.fingerprint.blank?

    bound = @genre.fingerprint.length < SHORT_FINGERPRINT ? 1 : MAX_DISTANCE
    distance = "levenshtein(genres.fingerprint, #{quote(@genre.fingerprint)})"
    Genre
      .where.not(id: @genre.id)
      .where(canonical_id: nil, hidden_at: nil, blocked_at: nil)
      .where('events_count > 0 OR parent_id IS NOT NULL')
      .select("genres.*, #{distance} AS distance")
      .where("#{distance} <= #{bound}")
      .order('distance ASC, events_count DESC, name ASC')
      .limit(limit)
  end
end
