require 'icalendar'

# Builds the subscribable ICS feed of a user's saved shows.
#
# Scoped to events from yesterday on, so a show drops off the calendar about a
# day after it happens — late enough that anything still in progress / running
# past midnight stays put, without hoarding the whole past. A live subscription
# re-fetches this, so there's nothing to delete: old events simply fall outside
# the window on the next refresh.
class SavedEventsCalendar
  # How long a timed show blocks out in a subscriber's calendar. Venues rarely
  # publish an end time, so we assume a typical evening's length.
  DEFAULT_DURATION = 3.hours

  def self.ics(user, now: Time.current)
    new(user, now: now).to_ical
  end

  def initialize(user, now: Time.current)
    @user = user
    @now = now
  end

  def events
    @user.saved_events
         .where('events.start_date >= ?', @now.to_date - 1)
         .includes(:locations, :styles)
         .order(:start_date, :start_time, :title)
  end

  def to_ical
    cal = Icalendar::Calendar.new
    cal.prodid = '-//üsgu//Saved shows//EN'
    I18n.with_locale(@user.locale.presence || I18n.default_locale) do
      cal.x_wr_calname = I18n.t('calendar_feed.name')
      events.each { |event| cal.add_event(build_event(event)) }
    end
    cal.publish
    cal.to_ical
  end

  private

  def build_event(event)
    Icalendar::Event.new.tap do |e|
      # Stable per event so a re-fetch updates the same entry instead of duplicating.
      e.uid     = "saved-event-#{event.id}@uesgu.ch"
      e.summary = event.cancelled? ? I18n.t('calendar_feed.cancelled_prefix', title: event.title) : event.title
      e.dtstamp = utc(event.updated_at)
      apply_times(e, event)
      e.location    = location_for(event)
      e.description = description_for(event)
      e.url         = event.url
      e.status      = 'CANCELLED' if event.cancelled?
    end
  end

  # A known start time → a timed block (emitted in UTC, which every client
  # localises). No usable time → an all-day entry, so a show whose time the
  # scraper couldn't read never lands at a misleading midnight. We treat an exact
  # 00:00 as "unknown" too: a genuine midnight start essentially never happens at
  # these venues, so it's almost always a placeholder. (DTEND is exclusive for
  # all-day entries, hence +1 day.)
  def apply_times(e, event)
    if timed?(event)
      e.dtstart = utc(event.start_time)
      e.dtend   = utc(event.start_time + DEFAULT_DURATION)
    else
      e.dtstart = Icalendar::Values::Date.new(event.start_date)
      e.dtend   = Icalendar::Values::Date.new(event.start_date + 1)
    end
  end

  # A UTC datetime value with the trailing "Z" — without the tzid the gem emits a
  # floating local time, which clients would show at the wrong wall-clock abroad.
  def utc(time)
    Icalendar::Values::DateTime.new(time.utc, 'tzid' => 'UTC')
  end

  def timed?(event)
    time = event.start_time
    return false if time.blank?

    !(time.hour.zero? && time.min.zero?)
  end

  def location_for(event)
    (event.venue&.name || event.locations.map(&:name).first).presence
  end

  def description_for(event)
    [event.subtitle.presence, event.styles.map(&:name).presence&.join(', '), event.url]
      .compact.join("\n")
  end
end
