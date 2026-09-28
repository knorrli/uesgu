module Scrapers
  class MahoganyHall < Agent
    self.opens_event_pages = true

    def self.url
      URI.parse("https://www.mahogany.ch/konzerte")
    end

    def event_rows
      page.css(".view-konzerte .views-row")
    end

    def event_url(row)
      absolute_url(row.at_css(".views-field-title .field-content a").attr("href"))
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

    def event_genre_prose(row)
      get(event_url(row)).css("article.node--type-konzert .node__content .text-formatted").map(&:text).join("\n")
    end
  end
end
