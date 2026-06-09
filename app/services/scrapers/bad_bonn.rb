module Scrapers
  class BadBonn < Agent
    def self.location
      'Bad Bonn'
    end

    def self.locations
      [location, 'Düdingen', 'FR']
    end

    def self.url
      URI.parse('https://club.badbonn.ch/program')
    end

    def process_events
      get(self.class.url)

      page.css('.program-row').each do |event_container|
        link = Page::Link.new(event_container.at_css('.program-bands a'), @mech, page)
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

    # The detail page carries the event data as data-* attributes on <article>.
    # (The element used to be `article.show`; the site dropped that class in a
    # Tailwind redesign, but the data attributes are stable.)
    def event_start_time(event_page:)
      article = event_page.at_css('article[data-date]')
      date_string = article&.attr('data-date').to_s
      time_string = article&.attr('data-time').to_s
      raise "Missing date (article[data-date]) on #{event_page.uri}" if date_string.blank?
      Time.zone.parse("#{date_string}, #{time_string}")
    end

    def event_title(event_page:)
      event_page.at_css('article[data-date]').attr('data-title').to_s
    end

    def event_subtitle(event_page:)
      event_page.css('article p').map { |node| node.text.squish }.find(&:present?).to_s
    end

    def event_genres(event_page:)
      nil
    end
  end
end
