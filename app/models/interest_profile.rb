class InterestProfile
  Criteria = Struct.new(:genres, :queries, :locations, keyword_init: true) do
    def taste? = genres.any? || queries.any? || locations.any?

    def match?(genre_names, location_names, haystack)
      genre_or_query =
        (genres.empty? && queries.empty?) ||
        genre_names.intersect?(genres) ||
        queries.any? { |term| haystack.include?(term) }
      location = locations.empty? || location_names.intersect?(locations)
      genre_or_query && location
    end
  end

  def self.for(user)
    return EMPTY unless user

    criteria = user.saved_filters.highlighting.filter_map do |saved|
      filter = Filter.build(queries: saved.queries, genres: saved.genres,
                            location_list: saved.location_list)
      candidate = Criteria.new(
        genres:    Set.new(filter.expanded_genre_names.map { |name| name.to_s.downcase }),
        queries:   filter.queries.map { |term| term.to_s.downcase.strip }.reject(&:blank?),
        locations: Set.new(filter.location_list.map { |name| name.to_s.downcase })
      )
      candidate if candidate.taste?
    end
    new(criteria)
  end

  def initialize(criteria)
    @criteria = criteria
    @matches = {}
  end

  def any? = @criteria.any?

  def interesting?(event) = matching(event).any?

  def why_genres(event)
    wanted = matching(event).reduce(Set.new) { |set, criteria| set | criteria.genres }
    return [] if wanted.empty?

    event.genres.select { |genre| wanted.include?(genre.name.to_s.downcase) }
  end

  def why_locations(event)
    wanted = matching(event).reduce(Set.new) { |set, criteria| set | criteria.locations }
    return [] if wanted.empty?

    event.locations.select { |location| wanted.include?(location.name.to_s.downcase) }
  end

  private

  def matching(event)
    return [] if @criteria.empty?

    @matches[event.id] ||= begin
      genre_names    = Set.new(event.genres.map { |genre| genre.name.to_s.downcase })
      location_names = Set.new(event.locations.map { |location| location.name.to_s.downcase })
      haystack       = [event.title, event.description, *event.genres.map(&:name)].compact.join(" ").downcase
      @criteria.select { |criteria| criteria.match?(genre_names, location_names, haystack) }
    end
  end

  EMPTY = new([])
end
