module CalendarHelper
  CalendarVenue = Struct.new(:name, :count, :favorite, keyword_init: true)
  CalendarHeadline = Struct.new(:venues, :extra, keyword_init: true)

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

  # The most-relevant venues to headline on a calendar cell (desktop, phase 2):
  # the venues of the day's SAVED events (the strongest signal) if any, else the
  # venues of events matching a FOLLOW (followed location/style), else nil — so a
  # generic events-only day shows no headline. Returns a CalendarHeadline with up
  # to two distinct venue names plus an `extra` overflow count: two names fit a
  # narrow column and 2+ saved shows a day is plausible, so we surface both and
  # spill the rest into a "+N more" line. All in-memory over the day's already-
  # loaded events. Venue (not title) — titles vary wildly and truncate uselessly.
  def calendar_day_headline(events)
    saved = events.select { |event| event_saved?(event) }
    source = saved.any? ? saved : events.select { |event| event_matches_follow?(event) }
    venues = source.filter_map { |event| event.venue&.name || event.locations.first&.name }.uniq
    return nil if venues.empty?

    CalendarHeadline.new(venues: venues.first(2), extra: [venues.size - 2, 0].max)
  end

  # The favoritable things happening on a day, as namespaced keys
  # ("l:<location>" / "s:<style>"). Rendered onto the cell's heart marker so the
  # favorite Stimulus controller can flip it the instant a matching tag is
  # toggled, without re-rendering the grid (and disturbing the open day drawer).
  def calendar_day_favorite_keys(events)
    events.flat_map { |event| event_follow_keys(event) }.uniq
  end

  # One event's follow keys ("l:<location>" / "s:<style>"). The per-event form of
  # calendar_day_favorite_keys: a date header carries the per-event lists so the
  # favorite controller can recount how many of the day's shows match the followed
  # set (the live ★ interest count) without a re-render.
  def event_follow_keys(event)
    event.locations.map { |location| "l:#{location.name}" } +
      event.styles.map { |style| "s:#{style.name}" }
  end
end
