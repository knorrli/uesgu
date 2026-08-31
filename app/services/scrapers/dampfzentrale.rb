module Scrapers
  class Dampfzentrale < Agent
    def self.url
      URI.parse("https://www.dampfzentrale.ch/")
    end

    field_gaps genres: :no_field

    def event_rows
      page.css(".event-entry")
    end

    def event_url(row)
      link = row.at_css("a.overlay-link")
      return if link.blank?

      URI.join(self.class.url, link.attr("href")).to_s
    end

    def event_start_time(content)
      meta = content.at_css(".event-meta")
      date_string = meta&.text.to_s[/\b(\d{1,2})\.(\d{1,2})\.(\d{2})\b/]
      raise "Unparseable Dampfzentrale date: #{meta&.text&.squish.inspect}" if date_string.blank?

      day, month, year = $1, $2, $3
      time_string = meta.at_css("time")&.text&.squish.to_s[/\d{1,2}:\d{2}/]
      Time.zone.parse("20#{year}-#{month}-#{day} #{time_string}")
    end

    def event_title(content)
      content.at_css(".event-information h2")&.text&.squish
    end

    def event_description(content)
      content.at_css(".event-information h3")&.text&.squish
    end

    def event_cancelled?(_event, content)
      content.classes.include?("abgesagt") || content.at_css(".banner.cancelled").present?
    end
  end
end
