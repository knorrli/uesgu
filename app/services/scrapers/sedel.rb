module Scrapers
  class Sedel < Agent
    def self.location
      'Sedel'
    end

    def self.locations
      [location, 'Luzern', 'LU']
    end

    def self.url
      URI.parse('https://sedel.ch')
    end

    def process_events
      get(self.class.url)

      page.css('.programm ul > li').each do |event_container|
        link = Page::Link.new(event_container.at_css('a'), @mech, page)
        url = URI.join(self.class.url, link.href).to_s

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
      date_string = event_page.css('time').attr('datetime')
      Time.zone.parse(date_string)
    end

    def event_title(event_page:)
      event_page.css('.field-name-node-title').text.split(' | ').compact_blank.map(&:squish).join(', ')
    end

    def event_subtitle(event_page:)
      event_page.css('.field-name-field-veranstalter').text.squish
    end

    def event_genres(event_page:)
      event_page.css('.field-name-field-stil-taxo').text.split(' | ').compact_blank.map(&:squish)
    end
  end
end
