module Scrapers
  class Roessli < Agent
    def self.url
      URI.parse("https://www.souslepont-roessli.ch/")
    end

    field_gaps description: :no_field

    def event_rows
      page.css(".rossli-events .event")
    end

    def event_url(row)
      URI.parse(row.at_css("a").attr("href").to_s).to_s
    end

    def self.event_url_pattern
      %r{\Ahttps://(?:www\.)?souslepont-roessli\.ch/}
    end

    def event_start_time(content)
      event_date_string = content.css(".event-date").attr("datetime").to_s
      /(?<day>\d{1,2})\.\s*(?<month>\p{L}+)\.?\s+(?<year>\d{4})/ =~ event_date_string
      /(?<time_string>\d{1,2}:\d{2})/ =~ event_date_string

      raise "Unparseable date #{event_date_string.inspect}" if day.blank? || month.blank? || year.blank?

      Time.zone.parse("#{year}-#{month_number(month: month)}-#{day} #{time_string}")
    end

    def event_title(content)
      content.css("h2").text.squish
    end

    def event_genres(content)
      content.css(".event-categories li").map { |category| category.text.squish }
    end
  end
end
