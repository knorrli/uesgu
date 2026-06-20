module Scrapers
  class MahoganyHall < Agent
    def self.location
      'Mahogany Hall'
    end

    def self.locations
      [location, 'Bern', 'BE']
    end

    def self.url
      URI.parse('https://www.mahogany.ch/konzerte')
    end

    def event_rows
      page.css('.view-konzerte .views-row')
    end

    def event_url(row)
      URI.join(self.class.url, row.at_css('.views-field-title .field-content a').attr('href')).to_s
    end

    def event_start_time(content)
      date_string = content.css('.views-field-field-tueroeffnung time').attr('datetime')
      Time.zone.parse(date_string)
    end

    def event_title(content)
      content.css('.views-field-title .field-content').text.squish
    end

    def event_subtitle(content)
      content.css('.views-field-field-subtitle .field-content').text.squish
    end

    # Freetext-mined: Mahogany Hall exposes NO dedicated genre field (verified
    # against the live markup — the event row carries only title/subtitle/teaser/
    # price). The subtitle mixes real genre lists ("dixieland, blues, gospel und
    # swing") with free-text prose ("big band goes modern grooves"). The 1–2-word
    # filter is a damage-limiter on what gets mined; leftover prose tokens now land
    # in the curation queue (filed, aliased, or blocked) rather than being dropped.
    def event_consumption_genres(content)
      event_subtitle(content)
        .split(/,|\s\-\s|\s[au]nd\s|&|\//)
        .map { |part| part.squish }
        .select { |part| part.split.size.between?(1, 2) }
        .map(&:titleize)
    end
  end
end
