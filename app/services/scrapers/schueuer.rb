module Scrapers
  class Schueuer < Agent
    def self.location
      'Schüür'
    end

    def self.locations
      [location, 'Luzern', 'LU']
    end

    def self.url
      URI.parse('https://www.schuur.ch/programm')
    end

    def process_events
      get(self.class.url)

      page.css('.viz-event-list-box').each do |event_container|
        url = URI.parse(event_container.at_css('a.viz-event-box-details-link').attr('href').to_s).to_s

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
      event_date_time = event_container.css('.viz-event-date').text.squish
      /(?<day>\d{1,2})\.\W*(?<month>\S*)\W*(?<year>\d{4})*/ =~ event_date_time
      /(?<hour>\d{1,2}):(?<minute>\d{1,2})/ =~ event_date_time

      raise "Unparseable date #{event_date_time.inspect}" if day.blank? || month.blank? || year.blank?

      Time.zone.parse("#{year}-#{month_number(month: month)}-#{day}, #{hour}:#{minute}")
    end

    def event_title(event_container:)
      event_container.css('.viz-event-name').text.squish
    end

    def event_subtitle(event_container:)
      event_container.css('.viz-event-headline').text.squish
    end

    def event_genres(event_container:)
      event_container.css('.viz-event-genre').map { |node| node.text.squish }
    end
  end
end
