module Scrapers
  class Dachstock < Agent
    def self.location
      "Dachstock"
    end

    def self.locations
      [location, "Bern", "BE"]
    end

    def self.url
      URI.parse("https://www.dachstock.ch/events")
    end

    def event_rows
      page.css(".event-list .event-teaser")
    end

    # Rows without a detail link are skipped (the base skips a blank url).
    def event_url(row)
      link = row.at_css(".event-teaser-info a.event-teaser-bottom")
      return if link.blank?

      URI.join(self.class.url, link.attr("href")).to_s
    end

    def event_start_time(content)
      date_string = content.css(".event-date").text.squish
      raise "Unparseable date #{date_string.inspect}" unless date_string =~ /\d{1,2}\.\d{1,2}\.\d{4}/
      Time.zone.parse(date_string)
    end

    def event_title(content)
      content.css(".event-teaser-info .event-title").text.squish
    end

    def event_description(content)
      content.css(".artist-list .artist-teaser").map do |node|
        artist_name = node.at_css(".artist-name").text.squish
        artist_info = node.at_css(".artist-info").text.squish
        artist = StringIO.new
        artist << artist_name
        artist << " (#{artist_info})" if artist_info.present?
        artist.string
      end.compact_blank.join(", ").presence
    end

    def event_genres(content)
      content.css(".event-teaser-info .event-teaser-tags .tag").map { |node| node.text.squish }
    end

    # The teaser sometimes carries only the support-act description and no title;
    # promote it so the event isn't left titleless.
    def postprocess(event)
      return if event.title.present?

      event.title = event.description
      event.description = nil
    end
  end
end
