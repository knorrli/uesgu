module Scrapers
  class Dachstock < Agent
    def self.location
      'Dachstock'
    end

    def self.locations
      [location, 'Reithalle', 'Bern', 'BE']
    end

    def self.url
      URI.parse('https://www.dachstock.ch/events')
    end

    def process_events
      get(self.class.url)

      page.css('.event-list .event-teaser').each do |event_container|
        link = event_container.at_css('.event-teaser-info a.event-teaser-bottom')
        next if link.blank?

        url = URI.join(self.class.url, link.attr('href')).to_s
        Rails.logger.info "Processing event URL #{url}"

        event = Event.find_or_initialize_by(url: url)
        event.start_time = event_start_time(event_container: event_container)
        event.start_date = event.start_time.to_date
        event.title = event_title(event_container: event_container)
        event.subtitle = event_subtitle(event_container: event_container)
        event.genre_list = event_genres(event_container: event_container)
        event.style_list = event_styles(genres: event.genre_list)
        event.location_list = self.class.locations

        if event.title.blank?
          event.title = event.subtitle
          event.subtitle = nil
        end

        event.save!
      rescue StandardError => e
        raise ScrapeError.new e.message, event
      end
    end

    def event_start_time(event_container:)
      date_string = event_container.css('.event-date').text.squish
      raise "Unparseable date #{date_string.inspect}" unless date_string =~ /\d{1,2}\.\d{1,2}\.\d{4}/
      Time.zone.parse(date_string)
    end

    def event_title(event_container:)
      event_container.css('.event-teaser-info .event-title').text.squish
    end

    def event_subtitle(event_container:)
      event_container.css('.artist-list .artist-teaser').map do |node|
        artist_name = node.at_css('.artist-name').text.squish
        artist_info = node.at_css('.artist-info').text.squish
        artist = StringIO.new
        artist << artist_name
        artist << " (#{artist_info})" if artist_info.present?
        artist.string
      end.compact_blank.join(', ')
    end

    def event_genres(event_container:)
      event_container.css('.event-teaser-info .event-teaser-tags .tag').map { |node| node.text.squish }
    end
  end
end
