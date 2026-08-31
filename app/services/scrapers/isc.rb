module Scrapers
  class Isc < Agent
    def self.url
      URI.parse("https://isc-club.ch/")
    end

    def initialize
      super
      @scrape_date = Date.current
    end

    def event_rows
      page.css("a.event_preview")
    end

    def skip_row?(row)
      !row.css(".event_title_info").text.squish.include?("Konzert")
    end

    def event_url(row)
      URI.parse(row.attr("href").to_s).to_s
    end

    def event_content(row)
      click(Page::Link.new(row, @mech, page))
    end

    def event_start_time(content)
      date_string = content.css(".event_detail_header .event_title_date").text.squish
      time_string = content.css(".event_detail .facts_listing").text.squish[/\d{1,2}:\d{1,2} Uhr/]

      /(?<day>\d{1,2})?\.(?<month>\d{1,2})?\./ =~ date_string
      /(?<hour>\d{1,2})?:(?<minute>\d{1,2})?/ =~ time_string

      raise "Unparseable date #{date_string.inspect}" if day.blank? || month.blank?

      Time.zone.parse("#{year_for(month.to_i, day.to_i)}-#{month}-#{day}, #{hour}:#{minute}")
    end

    def event_title(content)
      content.css(".event_detail_header .event_title_title").text.squish
    end

    def event_description(content)
      row = content.css(".event_detail .facts_listing .facts_listing_row").find do |node|
        node.at_css(".column_left")&.text&.squish&.start_with?("FFO")
      end
      bands = row&.at_css(".column_right")&.text&.squish
      "For fans of: #{bands}" if bands.present?
    end

    def event_genres(content)
      info = content.css(".event_detail_header .event_title_info").text.squish
      genres = info[/\s-\s(.+)\z/, 1].to_s
      genres.split(/,|\s[au]nd\s/).map(&:squish).compact_blank
    end

    private

    def year_for(month, day)
      year = @scrape_date.year
      year += 1 if Date.new(year, month, day) < @scrape_date
      year
    end
  end
end
