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
      # The subtitle is the only genre-ish field Mahogany Hall exposes, but it mixes
      # real genre lists ("dixieland, blues, gospel und swing") with free-text prose
      # ("big band goes modern grooves"). Split on the usual delimiters and keep only
      # short 1–2 word tokens: genres are short phrases, prose is not — so artist/show
      # blurbs stop landing as junk genres. (There is no dedicated genre field.)
      event_subtitle(content)
        .split(/,|\s\-\s|\s[au]nd\s|&|\//)
        .map { |part| part.squish }
        .select { |part| part.split.size.between?(1, 2) }
        .map(&:titleize)
    end
  end
end
