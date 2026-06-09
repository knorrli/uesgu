module Scrapers
  class NouveauMonde < Agent
    def self.location
      'Nouveau Monde'
    end

    def self.locations
      [location, 'Fribourg', 'FR']
    end

    def self.url
      URI.parse('https://www.nouveaumonde.ch/agenda/')
    end

    def process_events
      get(self.class.url)

      page.css('.poster[data-tofilter*=concert]').each do |event_container|
        link = Page::Link.new(event_container, @mech, page)
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
      date_string = event_page.css('#section-schedule').children.first.text.squish[/\d{1,2}\.\d{1,2}\.\d{4}/]
      time_string = event_page.css('#section-schedule .scheduleLine').find { |node| node.text.squish.starts_with?(/Beginn|Debut/) }.text.squish[/\d{1,2}h\d{1,2}/]
      raise "Unparseable date #{event_page.css('#section-schedule').children.first.text.squish.inspect}" if date_string.blank?
      Time.zone.parse("#{date_string}, #{time_string}")
    end

    def event_title(event_page:)
      event_page.css('.groupIntro').map do |node|
        country_code = node.css('.plateMedium').text.squish
        act_name = StringIO.new
        act_name << node.children.find { |child| child.name == 'h2' }.text
        act_name << " (#{country_code})" if country_code.present?
        act_name.string
      end.compact_blank.join(', ')
    end

    def event_subtitle(event_page:)
      nil
    end

    def event_genres(event_page:)
      main_tags = event_page.css('.plateSmall').map { |node| node.text.squish }
      artist_tags = event_page.css('.groupIntro .genTexArea h5').flat_map { |node| node.text.split(/,|\s\-\s|\s[au]nd\s|&|\//) }.map(&:squish).compact_blank
      (main_tags | artist_tags).sort
    end
  end
end
