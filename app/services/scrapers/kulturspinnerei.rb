require "cgi"
require "nokogiri"

module Scrapers
  class Kulturspinnerei < Agent
    def self.url
      URI.parse("https://kulturspinnerei.ch/wp-json/tribe/events/v1/events?per_page=50")
    end

    field_gaps genres: :dormant

    def event_rows
      Array(parse_json(page.body)["events"])
    end

    def event_url(row)
      row["url"].to_s
    end

    def event_start_time(row)
      stamp = row["start_date"].to_s
      raise "Unparseable Kulturspinnerei date: #{stamp.inspect}" if stamp.blank?

      Time.zone.parse(stamp)
    end

    def event_title(row)
      CGI.unescapeHTML(row["title"].to_s).squish
    end

    def event_description(row)
      html = row["description"].to_s.gsub(%r{</p>|</h3>|<br\s*/?>}i, " · ")
      Nokogiri::HTML.fragment(html).text.squish.presence
    end

    def event_genres(row)
      (Array(row["categories"]) + Array(row["tags"])).filter_map { |t| t["name"].presence }
    end

    def event_genre_prose(row)
      event_description(row)
    end
  end
end
