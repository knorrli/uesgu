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

    def process_events
      get(self.class.url)

      page.css('.view-konzerte .views-row').each do |event_container|
        url = URI.join(self.class.url, event_container.at_css('.views-field-title .field-content a').attr('href')).to_s
        Rails.logger.info "Processing event URL #{url}"

        event = Event.find_or_initialize_by(url: url)
        event.start_time = event_start_time(event_container: event_container)
        event.start_date = event.start_time.to_date
        event.title = event_title(event_container: event_container)
        event.subtitle = event_subtitle(event_container: event_container)
        event.genre_list = event_genres(event_container: event_container)
        event.style_list = event_styles(genres: event.genre_list)
        event.location_list = self.class.locations
        event.save!
      rescue StandardError => e
        record_failure(event, e)
      end
    end

    def event_start_time(event_container:)
      date_string = event_container.css('.views-field-field-tueroeffnung time').attr('datetime')
      Time.zone.parse(date_string)
    end

    def event_title(event_container:)
      event_container.css('.views-field-title .field-content').text.squish
    end

    def event_subtitle(event_container:)
      event_container.css('.views-field-field-subtitle .field-content').text.squish
    end

    def event_genres(event_container:)
      # make sure we don't add full sentences as genre tags
      event_subtitle(event_container: event_container).split(/,|\s\-\s|\s[au]nd\s|&|\//).map { |content| content.squish.titleize }.reject { |genre| genre.length > 30 }
    end
  end
end
