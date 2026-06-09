module Scrapers
  class Kofmehl < Agent
    def self.location
      'Kofmehl'
    end

    def self.locations
      [location, 'Solothurn', 'SO']
    end

    def self.url
      URI.parse('https://kofmehl.net/')
    end

    def process_events
      get(self.class.url)

      page.css('.events .events__element').each do |event_container|
        link = Page::Link.new(event_container.at_css('a.events__link'), @mech, page)
        url = URI.parse(link.href).to_s

        Rails.logger.info "Processing event URL #{url}"

        event = Event.find_or_initialize_by(url: url)
        transact do
          event_page = click(link)
          event.start_time = event_start_time(event_page: event_page)
          event.start_date = event.start_time.to_date
          event.title = event_title(event_page: event_page)
          event.subtitle = event_subtitle(event_page: event_page)
          event.genre_list = event_genres(event_page: event_page)
          event.style_list = event_styles(genres: event.genre_list)
          event.location_list = self.class.locations
          event.save!
        rescue StandardError => e
          record_failure(event, e)
        end
      end
    end

    def event_start_time(event_page:)
      date_string = event_page.css('.event__date').text.squish[/\d{1,2}\.\d{1,2}\.\d{4}/]
      time_string = event_page.css('.sidebar time').last&.text&.squish.try(:[], /\d{2}:\d{2}/)
      raise "Unparseable date #{event_page.css('.event__date').text.squish.inspect}" if date_string.blank?
      Time.zone.parse("#{date_string}, #{time_string}")
    end

    def event_title(event_page:)
      event_page.css('.event__title-artist').text.squish
    end

    def event_subtitle(event_page:)
      support = event_page.css('.event__support').text.squish
      subtitle = event_page.css('.event__subtitle').text.squish
      [support, subtitle].compact_blank.join(', ')
    end

    def event_genres(event_page:)
      nil
    end
  end
end
