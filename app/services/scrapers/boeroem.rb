module Scrapers
  class Boeroem < Agent
    def self.location
      'Böröm'
    end

    def self.locations
      [location, 'Aarau', 'AG']
    end

    def self.url
      URI.parse('https://boeroem.ch/')
    end

    def event_rows
      page.css('.ast-article-single .veranstaltung')
    end

    def event_url(row)
      URI.parse(link_for(row).href).to_s
    end

    def event_content(row)
      click(link_for(row))
    end

    def event_start_time(content)
      date_string = content.at_css('.event-single-datum').text.squish
      /(?<day>\d{1,2})\.\W*(?<month>\S*)\W*(?<year>\d{4})*/ =~ date_string

      time_string = content.css('.elementor-widget-container').select { |node| node.text.squish.starts_with?('Show Start') }.map(&:text).join[/\d{2}:\d{2}/]

      Time.zone.parse("#{year}-#{month_number(month: month)}-#{day}, #{time_string}")
    end

    def event_title(content)
      content.at_css('.elementor-top-section .elementor-widget-theme-post-title').text.squish
    end

    def event_subtitle(content)
      content.css('.elementor-top-section .event-single-untertitel').text.squish
    end

    private

    def link_for(row)
      Page::Link.new(row.at_css('.elementor-heading-title a'), @mech, page)
    end
  end
end
