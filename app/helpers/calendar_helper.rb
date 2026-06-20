module CalendarHelper
  CalendarHeadline = Struct.new(:venues, :extra, keyword_init: true)

  # The venues to headline on a calendar cell (desktop): the venues of the day's
  # SAVED events, else nil — so a generic events-only day shows no headline.
  # Returns a CalendarHeadline with up to two distinct venue names plus an `extra`
  # overflow count (two names fit a narrow column; the rest spill into a "+N more"
  # line). All in-memory over the day's already-loaded events. Venue (not title) —
  # titles vary wildly and truncate uselessly.
  def calendar_day_headline(events)
    saved = events.select { |event| event_saved?(event) }
    venues = saved.filter_map { |event| event.venue&.name || event.locations.first&.name }.uniq
    return nil if venues.empty?

    CalendarHeadline.new(venues: venues.first(2), extra: [venues.size - 2, 0].max)
  end
end
