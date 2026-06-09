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

    def event_rows
      page.css('.viz-event-list-box')
    end

    def event_url(row)
      URI.parse(row.at_css('a.viz-event-box-details-link').attr('href').to_s).to_s
    end

    def event_start_time(content)
      event_date_time = content.css('.viz-event-date').text.squish
      /(?<day>\d{1,2})\.\W*(?<month>\S*)\W*(?<year>\d{4})*/ =~ event_date_time
      /(?<hour>\d{1,2}):(?<minute>\d{1,2})/ =~ event_date_time

      raise "Unparseable date #{event_date_time.inspect}" if day.blank? || month.blank? || year.blank?

      Time.zone.parse("#{year}-#{month_number(month: month)}-#{day}, #{hour}:#{minute}")
    end

    def event_title(content)
      content.css('.viz-event-name').text.squish
    end

    def event_subtitle(content)
      content.css('.viz-event-headline').text.squish
    end

    def event_genres(content)
      content.css('.viz-event-genre').map { |node| node.text.squish }
    end
  end
end
