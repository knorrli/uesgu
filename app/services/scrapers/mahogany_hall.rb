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

    def event_genres(content)
      # make sure we don't add full sentences as genre tags
      event_subtitle(content).split(/,|\s\-\s|\s[au]nd\s|&|\//).map { |part| part.squish.titleize }.reject { |genre| genre.length > 30 }
    end
  end
end
