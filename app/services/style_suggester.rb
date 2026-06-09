class StyleSuggester
  include ActiveRecord::ConnectionAdapters::Quoting

  # Suggest styles for an unmapped genre, best guess first. Two signals,
  # strongest first:
  #   1. Co-occurrence — styles already on the events that carry this genre
  #      (contributed by those events' other genres). The events themselves tell
  #      us what the genre most likely is.
  #   2. Name similarity — styles of the most name-similar already-mapped genres
  #      (Levenshtein, via Postgres fuzzystrmatch). Fills in when a genre sits on
  #      events with no other mapped genres yet.
  def self.call(genre, limit: 5)
    new(genre).call(limit: limit)
  end

  def initialize(genre)
    @genre = genre
  end

  def call(limit: 5)
    (co_occurring_styles + similar_genre_styles).uniq.first(limit)
  end

  private

  def co_occurring_styles
    event_ids = ActsAsTaggableOn::Tagging
      .joins(:tag)
      .where(context: 'genres', taggable_type: Event.name, tags: { name: @genre.name })
      .select(:taggable_id)

    ranked_names = ActsAsTaggableOn::Tagging
      .joins(:tag)
      .where(context: 'styles', taggable_type: Event.name, taggable_id: event_ids)
      .group('tags.name')
      .count
      .sort_by { |_name, count| -count }
      .map(&:first)

    styles_by_name(ranked_names)
  end

  def similar_genre_styles
    Genre
      .where(id: Genre.assigned.select(:id))
      .where.not(id: @genre.id)
      .select("genres.*, levenshtein(genres.name, #{quote(@genre.name)}) AS distance")
      .order('distance ASC')
      .limit(20)
      .flat_map(&:styles)
      .uniq
  end

  # Map style names back to Style records, preserving the given order.
  def styles_by_name(names)
    by_name = Style.where(name: names).index_by(&:name)
    names.filter_map { |name| by_name[name] }
  end
end
