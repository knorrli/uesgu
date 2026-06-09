module Scrapers
  class Kiff < Agent
    def self.location
      'KIFF'
    end

    def self.locations
      [location, 'Aarau', 'AG']
    end

    def self.url
      URI.parse('https://www.kiff.ch/programm')
    end

    def process_events
      get(self.class.url)

      page.css('.FilterPage__FilterResults > .Card-Event').each do |event_container|
        link = Page::Link.new(event_container.at_css('.Card__Link'), @mech, page)
        url = URI.parse(link.href).to_s

        Rails.logger.info "Processing event URL #{url}"

        event = Event.find_or_initialize_by(url: url)
        event.start_time = Time.zone.parse(event_container.css('.Card__Date time').attr('datetime'))
        event.start_date = event.start_time.to_date

        transact do
          event_page = click(link)
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

    def event_title(event_page:)
      event_page.css('.EventPage__Subtitle h2').children.map do |node|
        next ',' if node.name == 'br'
        next "(#{node.text.squish})" if node['class'] == 'Act__country-code' && node.text.squish.present?

        node.text.squish
      end.compact_blank.join(' ')
    end

    def event_subtitle(event_page:)
      event_page.css('.EventPage__SupportActs').children.map do |node|
        next if node.text.squish.blank?

        act_list = node.css('.Act').map do |act|
          country_code = act.css('.Act__country-code').text.squish
          act_name = StringIO.new
          act_name << act.css('.Act__name').text.squish
          act_name << " (#{country_code})" if country_code.present?
          act_name.string.presence || act.text
        end.compact_blank.join(', ')

        "#{node.css('dt').text.squish}: #{act_list}".presence || node.text
      end.compact_blank.join("\n")
    end

    def event_genres(event_page:)
      event_page.css('.EventPage__Tags').children.map { |node| node.text.squish }.compact_blank
    end
  end
end
