module Scrapers
  class Gaskessel < Agent
    def self.location
      'Gaskessel'
    end

    def self.locations
      [location, 'Bern', 'BE']
    end

    def self.url
      URI.parse('https://gaskessel.ch/programm/')
    end

    def process_events
      get(self.class.url)

      page.css('.eventpreview').each do |event_container|
        url = URI.join(self.class.url, event_container.at_css('a.previewlink').attr('data-url')).to_s
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
        raise ScrapeError.new e.message, event
      end
    end

    def event_start_time(event_container:)
      date_string = event_container.css('.previewlink .eventdatum').text.squish
      time_string = event_container.css('.infobox .tcell').children.select { |node| node.text.squish =~ /^\d{1,2}:\d{1,2}$/ }.map(&:text).join

      /(?<day>\d{1,2})?\.(?<month>\d{1,2})?\.(?<year>\d+)/ =~ date_string
      /(?<hour>\d{1,2})?:(?<minute>\d{1,2})?/ =~ time_string

      raise "Unparseable date #{date_string.inspect}" if day.blank? || month.blank? || year.blank?

      Time.zone.parse("20#{year}-#{month}-#{day} #{hour}:#{minute}")
    end

    def event_title(event_container:)
      title = event_container.css('.eventname').text.squish
      title.presence || event_container.at_css('p').children.map do |node|
        next "(#{node.text.squish})" if node.name == 'sup' && node.text.squish.present?

        node.text.squish
      end.compact_blank.join(' ')
    end

    def event_subtitle(event_container:)
      event_container.css('.subtitle').text.split(',').map { |content| content.squish }.compact_blank.join(', ')
    end

    def event_genres(event_container:)
      event_container.css('.eventgenre').map { |node| node.text }.compact_blank.map(&:squish)
    end
  end
end
