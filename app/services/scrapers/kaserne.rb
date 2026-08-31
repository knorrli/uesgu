module Scrapers
  class Kaserne < Agent
    def self.url
      URI.parse("https://kaserne-basel.ch/de")
    end

    field_gaps description: :no_field, genres: :no_field

    def event_rows
      page.css(".index details.concert-type")
    end

    def event_url(row)
      link = row.at_css('a[href^="/de/events/"]')
      return if link.blank?

      URI.join(self.class.url, link.attr("href")).to_s
    end

    def event_start_time(content)
      atcb = content.at_css("add-to-calendar-button")
      date = atcb&.attr("startdate")
      raise "Missing Kaserne startdate for #{event_url(content)}" if date.blank?

      time = content.at_css(".times time")&.text&.squish.presence || atcb.attr("starttime")
      Time.zone.parse("#{date} #{time}")
    end

    def event_title(content)
      content.at_css("add-to-calendar-button")&.attr("name")&.strip
    end
  end
end
