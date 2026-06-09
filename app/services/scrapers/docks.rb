module Scrapers
  class Docks < Agent
    def self.location
      'Docks'
    end

    def self.locations
      [location, 'Lausanne', 'VD']
    end

    def self.url
      URI.parse('https://www.docks.ch/programme')
    end

    def process_events
      get(self.class.url)

      page.css('.programme-container .mix.concerts').each do |event_container|
        link = Page::Link.new(event_container.at_css('a'), @mech, page)
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
      date_string = event_page.css('.event-infos .event-info-date').text.squish[/\d{1,2}\.\d{1,2}\.\d{4}/]
      time_string = event_page.css('.event-infos .event-info-door').last.text.squish[/\d{2}:\d{2}/]
      Time.zone.parse("#{date_string}, #{time_string}")
    end

    def event_title(event_page:)
      event_page.css('.top-event-container h1').text.squish
    end

    def event_subtitle(event_page:)
      event_page.css('.event-subtitle').text.split('+').map { |content| content.squish }.compact_blank.join(', ')
    end

    def event_genres(event_page:)
      main_tags = event_page.css('.event-info-style').flat_map { |node| node.text.split('/').map(&:squish) }.compact_blank.map { |content| content.squish.titleize }
      artist_tags = event_page.css('.artist-item .artist-info').map { |node| node.text.squish }.compact_blank.map { |content| content.squish.titleize }
      (main_tags | artist_tags).sort
    end
  end
end
