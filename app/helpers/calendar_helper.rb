module CalendarHelper
  CalendarVenue = Struct.new(:name, :count, :favorite, keyword_init: true)

  # Glanceable summary for a calendar cell: distinct venue labels for the day's
  # events (deduped with a count), favorited venues first, then busiest. Titles
  # are intentionally dropped — they never fit a 1/7-width column, and the full
  # detail is one tap away in the day-detail panel.
  def calendar_day_venues(events, favorites: [])
    events
      .group_by { |event| event.venue&.name || event.locations.first&.name }
      .reject { |name, _| name.blank? }
      .map { |name, evs| CalendarVenue.new(name: name, count: evs.size, favorite: favorites.include?(name)) }
      .sort_by { |venue| [venue.favorite ? 0 : 1, -venue.count, venue.name] }
  end

  # The favoritable things happening on a day, as namespaced keys
  # ("l:<location>" / "s:<style>"). Rendered onto the cell's heart marker so the
  # favorite Stimulus controller can flip it the instant a matching tag is
  # toggled, without re-rendering the grid (and disturbing the open day drawer).
  def calendar_day_favorite_keys(events)
    events.flat_map do |event|
      event.locations.map { |location| "l:#{location.name}" } +
        event.styles.map { |style| "s:#{style.name}" }
    end.uniq
  end
end
