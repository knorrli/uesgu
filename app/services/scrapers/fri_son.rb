module Scrapers
  class FriSon < Agent
    def self.location
      'FriSon'
    end

    def self.locations
      [location, 'Fribourg', 'FR']
    end

    def self.url
      URI.parse('https://www.fri-son.ch/fr/programme?f%5B0%5D=category%3A1')
    end

    def process_events
      get(self.class.url)

      page.css('.view-events .node--type-event').each do |event_container|
        url = URI.join(self.class.url, event_container.at_css('a').attr('href')).to_s
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
      date_string = event_container.css('.field.field--name-field-date .datetime').attr('datetime')
      date = Time.zone.parse(date_string).to_date.iso8601
      time_string = event_container.css('.field.field--name-field-time-doors').text.squish
      Time.zone.parse("#{date}, #{time_string}")
    end

    def event_title(event_container:)
      event_container.css('.performers.main .performer').children.map do |node|
        next "(#{node.text.squish})" if node.name == 'sup' && node.text.squish.present?
        node.text.squish
      end.compact_blank.join(' ')
    end

    def event_subtitle(event_container:)
      event_container.css('.performers.standard .performer').map do |node|
        node.children.map  do |child|
          next "(#{child.text.squish})" if child.name == 'sup' && child.text.squish.present?
          child.text.squish
        end.compact_blank.join(' ')
      end.compact_blank.join(', ')
    end

    def event_genres(event_container:)
      event_container.css('.genre-wrapper .field__item').map { |tag| tag.text.squish }
    end
  end
end
