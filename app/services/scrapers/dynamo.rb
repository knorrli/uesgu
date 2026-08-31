require "cgi"

module Scrapers
  class Dynamo < Agent
    def self.venue_domains = ["dynamo.ch"]

    CONCERT_TID = 20
    GENRE_BY_TID = {
      14 => "Metal", 15 => "Hip-Hop", 16 => "Elektro",
      17 => "Hardcore/Punk", 18 => "Pop", 32 => "Rock/Indie"
    }.freeze

    def self.url
      params = {
        "filter[field_event_date.value][operator]" => ">",
        "filter[field_event_date.value][value]" => Date.current.iso8601,
        "sort" => "field_event_date.value",
        "page[limit]" => "50"
      }
      query = params.map { |k, v| "#{CGI.escape(k)}=#{CGI.escape(v)}" }.join("&")
      URI.parse("https://dynamo.nodehive.app/jsonapi/node/event?#{query}")
    end

    field_gaps description: :no_field

    def event_rows
      Array(parse_json(page.body, default: {})["data"])
    end

    def skip_row?(row)
      category_tids(row).exclude?(CONCERT_TID)
    end

    def event_url(row)
      alias_path = row.dig("attributes", "path", "alias")
      "https://www.dynamo.ch#{alias_path}" if alias_path.present?
    end

    def self.event_url_pattern
      %r{\Ahttps://www\.dynamo\.ch/}
    end

    def event_start_time(row)
      value = row.dig("attributes", "field_event_date", "value")
      raise "Missing Dynamo date for #{event_url(row)}" if value.blank?

      Time.zone.parse(value)
    end

    def event_title(row)
      row.dig("attributes", "field_title").to_s.squish
    end

    def event_genres(row)
      category_tids(row).filter_map { |tid| GENRE_BY_TID[tid] }
    end

    private

    def category_tids(row)
      Array(row.dig("relationships", "field_categories", "data"))
        .filter_map { |term| term.dig("meta", "drupal_internal__target_id") }
    end
  end
end
