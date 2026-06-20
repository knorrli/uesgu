# Derives "what could interest me" from a user's saved filters, so the events
# list/calendar can highlight matching shows WITHOUT the user applying each filter
# in turn. A pure in-memory predicate over the user's handful of saved filters,
# built once per request (see EventsHelper#interest_profile) and matched against
# the already-loaded event genres/locations — no per-filter query, no N+1.
#
# Match semantics mirror the saved filter MINUS its date window (the window drives
# notification cadence, not taste): a show is "of interest" when it satisfies some
# saved filter's non-blank taste dimensions —
#
#   (genre-subtree OR free-text query) AND location
#
# exactly as Filter#ransack_query combines them, just without the date clause.
# Filters with no taste dimension at all (a pure date window) are ignored, so an
# "everything this weekend" rule never paints the whole list.
class InterestProfile
  # One saved filter reduced to the lowercased sets we match against. Genres are
  # pre-expanded over the tree (a "Rock" filter carries "Shoegaze" et al.).
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

    criteria = user.saved_filters.filter_map do |saved|
      # Strip the date window: build a Filter from the taste dimensions only, reusing
      # its tree expansion so a parent-genre filter matches its descendants.
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

  # Does the user have any taste-bearing saved filter? (Lets callers skip work.)
  def any? = @criteria.any?

  def interesting?(event) = matching(event).any?

  # The event's OWN genres (original case) that explain a match — those in some
  # matching filter's expanded genre set. Drives the "why" flag on a genre pill.
  def why_genres(event)
    wanted = matching(event).reduce(Set.new) { |set, criteria| set | criteria.genres }
    return [] if wanted.empty?

    event.genres.select { |genre| wanted.include?(genre.name.to_s.downcase) }
  end

  # The event's OWN locations (venue / city / canton) that explain a match. Drives
  # the "why" flag on the venue header.
  def why_locations(event)
    wanted = matching(event).reduce(Set.new) { |set, criteria| set | criteria.locations }
    return [] if wanted.empty?

    event.locations.select { |location| wanted.include?(location.name.to_s.downcase) }
  end

  private

  # The saved filters this event matches, memoised per event for the request.
  def matching(event)
    return [] if @criteria.empty?

    @matches[event.id] ||= begin
      genre_names    = Set.new(event.genres.map { |genre| genre.name.to_s.downcase })
      location_names = Set.new(event.locations.map { |location| location.name.to_s.downcase })
      haystack       = [event.title, event.subtitle, *event.genres.map(&:name)].compact.join(" ").downcase
      @criteria.select { |criteria| criteria.match?(genre_names, location_names, haystack) }
    end
  end

  # Shared no-saved-filters profile: every predicate short-circuits to empty.
  EMPTY = new([])
end
