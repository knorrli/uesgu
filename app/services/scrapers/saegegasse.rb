module Scrapers
  class Saegegasse < Agent
    def self.location
      'Sägegasse'
    end

    def self.locations
      [location, 'Burgdorf', 'BE']
    end

    def self.url
      URI.parse('https://www.saegegasse.ch/programm')
    end

    def event_rows
      page.css('.rs_events_container .rs_event_detail')
    end

    def event_url(row)
      URI.join(self.class.url, row.at_css('a.rs_event_link').attr('href')).to_s
    end

    # The list page carries schema.org microdata, so the start time is a clean ISO
    # datetime (full date + time + year) — no text parsing, no silent-today risk.
    def event_start_time(content)
      date_string = content.at_css('meta[itemprop="startDate"]')&.attr('content')
      raise "Unparseable date #{date_string.inspect}" if date_string.blank?

      Time.zone.parse(date_string)
    end

    def event_title(content)
      content.css('.rsepro-title-block').text.squish
    end

    def event_subtitle(content)
      content.css('.rsepro-small-description-block').text.squish
    end
  end
end
