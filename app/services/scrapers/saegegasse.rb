module Scrapers
  class Saegegasse < Agent
    def self.location
      'Sägegasse'
    end

    def self.locations
      [location, 'Burgdorf', 'BE']
    end

    def self.url
      URI.parse('https://www.saegegasse.ch/programm')
    end

    def process_events
      get(self.class.url)

      page.css('.rs_events_container .rs_event_detail').each do |event_container|
        url = URI.join(self.class.url, event_container.at_css('a.rs_event_link').attr('href')).to_s
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

    # The list page carries schema.org microdata, so the start time is a clean ISO
    # datetime (full date + time + year) — no text parsing, no silent-today risk.
    def event_start_time(event_container:)
      date_string = event_container.at_css('meta[itemprop="startDate"]')&.attr('content')
      raise "Unparseable date #{date_string.inspect}" if date_string.blank?

      Time.zone.parse(date_string)
    end

    def event_title(event_container:)
      event_container.css('.rsepro-title-block').text.squish
    end

    def event_subtitle(event_container:)
      event_container.css('.rsepro-small-description-block').text.squish
    end

    def event_genres(event_container:)
      nil
    end
  end
end
