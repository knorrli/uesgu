module Scrapers
  class Roessli < Agent
    def self.location
      'Rössli'
    end

    def self.locations
      [location, 'Bern', 'BE']
    end

    def self.url
      URI.parse('https://www.souslepont-roessli.ch/')
    end

    # Rössli lists a title + categories (extracted as genres) but no description line.
    field_gaps description: :no_field

    def event_rows
      page.css('.rossli-events .event')
    end

    def event_url(row)
      URI.parse(row.at_css('a').attr('href').to_s).to_s
    end

    # The anchor hrefs drop the `www.` the feed host carries, so pin the bare host
    # (allowing either) for the golden-suite URL assertion.
    def self.event_url_pattern
      %r{\Ahttps://(?:www\.)?souslepont-roessli\.ch/}
    end

    def event_start_time(content)
      # e.g. "So., 7. Juni 2026 20:00 - 23:30" or a range
      # "Do., 11. Juni 2026 - Fr., 12. Juni 2026 21:00 - 2:30" (use the start date/time)
      event_date_string = content.css('.event-date').attr('datetime').to_s
      /(?<day>\d{1,2})\.\s*(?<month>\p{L}+)\.?\s+(?<year>\d{4})/ =~ event_date_string
      /(?<time_string>\d{1,2}:\d{2})/ =~ event_date_string

      raise "Unparseable date #{event_date_string.inspect}" if day.blank? || month.blank? || year.blank?

      Time.zone.parse("#{year}-#{month_number(month: month)}-#{day} #{time_string}")
    end

    def event_title(content)
      content.css('h2').text.squish
    end

    def event_genres(content)
      content.css('.event-categories li').map { |category| category.text.squish }
    end
  end
end
