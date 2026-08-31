module Scrapers
  class RoteFabrik < Agent
    def self.url
      URI.parse("https://kalender.rotefabrik.ch/api/events?categories=konzert")
    end

    def event_rows
      body = parse_json(page.body, default: {})
      body.is_a?(Hash) ? body.values : Array(body)
    end

    def event_url(row)
      id = row["id"]
      "https://rotefabrik.ch/de/programm.html#/events/#{id}" if id.present?
    end

    def self.event_url_pattern
      %r{\Ahttps://rotefabrik\.ch/de/programm\.html#/events/\d+\z}
    end

    def event_start_time(row)
      date = row["date"].to_s[/\d{4}-\d{2}-\d{2}/]
      raise "Unparseable Rote Fabrik date: #{row['date'].inspect}" if date.blank?

      time = (row["from"].presence || row["door"]).to_s[/\d{1,2}:\d{2}/]
      Time.zone.parse("#{date} #{time}")
    end

    def event_title(row)
      row.dig("rf_event", "title").to_s.squish
    end

    def event_description(row)
      row.dig("rf_event", "subtitle").to_s.squish.presence
    end

    field_gaps genres: :dormant

    def event_genres(row)
      Array(row.dig("rf_event", "tags")).map { |t| (t.is_a?(Hash) ? t["name"] : t).to_s.squish }.compact_blank
    end

    def event_genre_prose(row)
      html = row.dig("rf_event", "description").to_s
      Nokogiri::HTML(html).text if html.present?
    end
  end
end
