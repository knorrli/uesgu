module Scrapers
  class MahoganyHall < Agent
    def self.url
      URI.parse("https://www.mahogany.ch/konzerte")
    end

    def event_rows
      page.css(".view-konzerte .views-row")
    end

    def event_url(row)
      URI.join(self.class.url, row.at_css(".views-field-title .field-content a").attr("href")).to_s
    end

    def event_start_time(content)
      date_string = content.css(".views-field-field-tueroeffnung time").attr("datetime")
      Time.zone.parse(date_string)
    end

    def event_title(content)
      content.css(".views-field-title .field-content").text.squish
    end

    def event_description(content)
      content.css(".views-field-field-subtitle .field-content").text.squish
    end

    def event_genres(content)
      event_description(content)
        .split(/,|\s\-\s|\s[au]nd\s|&|\//)
        .map { |part| part.squish }
        .select { |part| part.split.size.between?(1, 2) }
        .map(&:titleize)
    end
  end
end
