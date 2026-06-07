module Scrapers
  class Isc < Agent
    attr_reader :current_year, :last_start_time

    def self.location
      'ISC'
    end

    def self.locations
      [location, 'Bern', 'BE']
    end

    def self.url
      URI.parse('https://isc-club.ch/')
    end

    def initialize
      super
      @current_year = Date.current.year
    end

    def process_events
      get(self.class.url)

      page.css('a.event_preview').each do |event_container|
        url = URI.parse(event_container.attr('href').to_s).to_s

        if skip_event?(event_container: event_container)
          Rails.logger.info "Skipping event URL #{url}"
          next
        end

        link = Page::Link.new(event_container, @mech, page)

        Rails.logger.info "Processing event URL #{url}"
        event = Event.find_or_initialize_by(url: url)
        transact do
          event_page = click(link)

          preprocess(event_page: event_page)

          event.start_time = event_start_time(event_page: event_page)
          event.start_date = event.start_time.to_date
          event.title = event_title(event_page: event_page)
          event.subtitle = event_subtitle(event_page: event_page)
          event.genre_list = event_genres(event_page: event_page)
          event.style_list = event_styles(genres: event.genre_list)
          event.location_list = self.class.locations
          event.save!
        rescue StandardError => e
          raise ScrapeError.new e.message, event
        end
      end
    end

    def skip_event?(event_container:)
      !event_container.css('.event_title_info').text.squish.include?('Konzert')
    end

    def event_start_time(event_page:)
      date_string = event_page.css('.event_detail_header .event_title_date').text.squish
      time_string = event_page.css('.event_detail .facts_listing').text.squish[/\d{1,2}:\d{1,2} Uhr/]

      /(?<day>\d{1,2})?\.(?<month>\d{1,2})?\./ =~ date_string
      /(?<hour>\d{1,2})?:(?<minute>\d{1,2})?/ =~ time_string

      raise "Unparseable date #{date_string.inspect}" if day.blank? || month.blank?

      @last_start_time = Time.zone.parse("#{current_year}-#{month}-#{day}, #{hour}:#{minute}")
    end

    def event_title(event_page:)
      event_page.css('.event_detail_header .event_title_title').text.squish
    end

    def event_subtitle(event_page:)
      event_page.css('.event_detail_header .event-subtitle').text.split('+').map { |content| content.squish }.compact_blank.join(', ')
    end

    def event_genres(event_page:)
      event_page.css('.event_detail_header .event_title_info').text.split(/,|\s-\s|\s[au]nd\s/).compact_blank.map(&:squish)
    end

    def preprocess(event_page:)
      if last_start_time && last_start_time > event_start_time(event_page: event_page)
        @current_year += 1
      end
    end
  end
end
