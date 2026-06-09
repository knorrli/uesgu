module Scrapers
  class Isc < Agent
    attr_reader :current_year, :last_start_time

    def self.location
      'ISC'
    end

    def self.locations
      [location, 'Bern', 'BE']
    end

    def self.url
      URI.parse('https://isc-club.ch/')
    end

    def initialize
      super
      @current_year = Date.current.year
    end

    def event_rows
      page.css('a.event_preview')
    end

    # Only concerts; other event types are skipped.
    def skip_row?(row)
      !row.css('.event_title_info').text.squish.include?('Konzert')
    end

    def event_url(row)
      URI.parse(row.attr('href').to_s).to_s
    end

    def event_content(row)
      click(Page::Link.new(row, @mech, page))
    end

    # The detail page omits the year; track the last start time and roll the year
    # over when the date sequence wraps backwards.
    def preprocess(content)
      if last_start_time && last_start_time > event_start_time(content)
        @current_year += 1
      end
    end

    def event_start_time(content)
      date_string = content.css('.event_detail_header .event_title_date').text.squish
      time_string = content.css('.event_detail .facts_listing').text.squish[/\d{1,2}:\d{1,2} Uhr/]

      /(?<day>\d{1,2})?\.(?<month>\d{1,2})?\./ =~ date_string
      /(?<hour>\d{1,2})?:(?<minute>\d{1,2})?/ =~ time_string

      raise "Unparseable date #{date_string.inspect}" if day.blank? || month.blank?

      @last_start_time = Time.zone.parse("#{current_year}-#{month}-#{day}, #{hour}:#{minute}")
    end

    def event_title(content)
      content.css('.event_detail_header .event_title_title').text.squish
    end

    def event_subtitle(content)
      content.css('.event_detail_header .event-subtitle').text.split('+').map { |part| part.squish }.compact_blank.join(', ')
    end

    def event_genres(content)
      content.css('.event_detail_header .event_title_info').text.split(/,|\s-\s|\s[au]nd\s/).compact_blank.map(&:squish)
    end
  end
end
