module CalendarHelper
  CalendarVenue = Struct.new(:name, :count, :favorite, keyword_init: true)

  # Event count at which a day's busyness meter reaches full width. Real days
  # cluster in the 1–6 range, so this caps a rare 10-event day from flattening
  # the scale for everything below it (those just peg at 100%).
  CALENDAR_LOAD_SATURATION = 8

  # Maps a day's event count to a 0–1 "busyness" fraction driving the width of the
  # cell's meter bar. Linear and honest at the low end (a 1-event day reads as a
  # short stub); CSS gives the fill a small min-width so any event day still shows.
  def calendar_day_load(count)
    return 0.0 if count.to_i <= 0

    [count.to_f / CALENDAR_LOAD_SATURATION, 1.0].min.round(3)
  end

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
