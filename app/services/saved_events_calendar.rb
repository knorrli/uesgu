require "icalendar"

class SavedEventsCalendar
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
         .where("events.start_date >= ?", @now.to_date - 1)
         .includes(:locations, :genres)
         .order(:start_date, :start_time, :title)
  end

  def to_ical
    cal = Icalendar::Calendar.new
    cal.prodid = "-//üsgu//Saved shows//EN"
    I18n.with_locale(@user.locale.presence || I18n.default_locale) do
      cal.x_wr_calname = I18n.t("calendar_feed.name")
      events.each { |event| cal.add_event(build_event(event)) }
    end
    cal.publish
    cal.to_ical
  end

  private

  def build_event(event)
    Icalendar::Event.new.tap do |e|
      e.uid     = "saved-event-#{event.id}@#{AppHost::CODE}"
      e.summary = event.cancelled? ? I18n.t("calendar_feed.cancelled_prefix", title: event.title) : event.title
      e.dtstamp = utc(event.updated_at)
      apply_times(e, event)
      e.location    = location_for(event)
      e.description = description_for(event)
      e.url         = event.url
      e.status      = "CANCELLED" if event.cancelled?
    end
  end

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
    Icalendar::Values::DateTime.new(time.utc, "tzid" => "UTC")
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
    [event.description.presence, event.genres.map(&:name).presence&.join(", "), event.url]
      .compact.join("\n")
  end
end
