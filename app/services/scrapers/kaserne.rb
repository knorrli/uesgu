module Scrapers
  class Kaserne < Agent
    def self.location
      "Kaserne Basel"
    end

    def self.locations
      [location, "Basel", "BS"]
    end

    # The /de homepage is the event index (SvelteKit SSR — all events in the HTML).
    def self.url
      URI.parse("https://kaserne-basel.ch/de")
    end

    # Kaserne's SvelteKit listing exposes a title + date only — no description line
    # and no genre/style/tag field.
    field_gaps description: :no_field, genres: :no_field

    # Each event is a <details> whose class encodes the category; `concert-type`
    # is the music filter (the venue also programmes dance/discourse).
    def event_rows
      page.css(".index details.concert-type")
    end

    def event_url(row)
      link = row.at_css('a[href^="/de/events/"]')
      return if link.blank?

      URI.join(self.class.url, link.attr("href")).to_s
    end

    # Title/date/doors are carried as clean attributes on the calendar-button
    # widget; the visible title is a styled image, so the attributes are the
    # reliable source. `startdate` is ISO with the year — no inference needed.
    def event_start_time(content)
      atcb = content.at_css("add-to-calendar-button")
      date = atcb&.attr("startdate")
      raise "Missing Kaserne startdate for #{event_url(content)}" if date.blank?

      # The visible start (span.times) is the show time; fall back to the widget's
      # starttime (doors) when the venue lists only one.
      time = content.at_css(".times time")&.text&.squish.presence || atcb.attr("starttime")
      Time.zone.parse("#{date} #{time}")
    end

    def event_title(content)
      content.at_css("add-to-calendar-button")&.attr("name")&.strip
    end
  end
end
