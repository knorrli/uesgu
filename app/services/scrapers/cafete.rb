module Scrapers
  class Cafete < Agent
    def self.url
      URI.parse("https://cafete.ch/")
    end

    def event_rows
      page.css(".event")
    end

    def event_url(row)
      key = row.at_css(".date")&.text&.parameterize
      "#{self.class.url}##{key}" if key.present?
    end

    def event_start_time(content)
      date_line = content.at_css(".date")&.text.to_s
      /(?<day>\d{1,2})\.\s*(?<month>\p{L}+)\s+(?<year>\d{4})/ =~ date_line
      time = date_line[/\d{1,2}:\d{2}/]
      raise "Unparseable Cafete date: #{date_line.inspect}" if day.blank? || month.blank? || year.blank?

      Time.zone.parse("#{year}-#{month_number(month: month)}-#{day} #{time}")
    end

    def event_title(content)
      content.at_css(".title")&.text&.squish
    end

    def event_description(content)
      content.at_css(".description")&.text&.squish.presence
    end

    def event_genres(content)
      content.at_css(".style")&.text.to_s
             .sub(/\A\s*Style:\s*/i, "")
             .split("/").map(&:squish).compact_blank
    end
  end
end
