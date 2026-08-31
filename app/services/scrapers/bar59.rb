module Scrapers
  class Bar59 < Agent
    def self.venue_domains = ["bar59.ch"]

    API_KEY = "AIzaSyDALptf6C6dG09tEfMdikBrMSAPPZqyHgk".freeze
    BASE = "https://firestore.googleapis.com/v1/projects/bar59-b8e95/databases/(default)/documents/events?key=#{API_KEY}&pageSize=300&orderBy=date%20desc".freeze

    def self.url
      URI.parse(BASE)
    end

    field_gaps description: :no_field

    def event_rows
      docs = all_documents
      docs.map { |doc| flatten(doc) }
          .select { |row| row["isActive"] && row["date"] && Date.parse(row["date"]) >= Date.current }
    end

    def event_url(row)
      "https://www.bar59.ch/#event-#{row['id']}" if row["id"].present?
    end

    def self.event_url_pattern
      %r{\Ahttps://www\.bar59\.ch/#event-}
    end

    def event_start_time(row)
      date = row["date"].to_s[/\d{4}-\d{2}-\d{2}/]
      raise "Unparseable Bar 59 date: #{row['date'].inspect}" if date.blank?

      time = row["startTime"].to_s[/\d{1,2}:\d{2}/]
      Time.zone.parse("#{date} #{time}")
    end

    def event_title(row)
      row["title"].to_s.squish
    end

    def event_genres(row)
      row["genre"].to_s.split(",").map(&:squish).compact_blank
    end

    private

    def all_documents
      body = JSON.parse(page.body)
      docs = Array(body["documents"])
      token = body["nextPageToken"]
      while token.present? && upcoming_on?(docs.last) && (resp = get("#{BASE}&pageToken=#{token}"))
        body = JSON.parse(resp.body)
        docs.concat(Array(body["documents"]))
        token = body["nextPageToken"]
      end
      docs
    end

    def upcoming_on?(doc)
      stamp = doc&.dig("fields", "date", "timestampValue").to_s[/\d{4}-\d{2}-\d{2}/]
      stamp.nil? || Date.parse(stamp) >= Date.current
    end

    def flatten(doc)
      fields = doc["fields"] || {}
      {
        "id" => doc["name"].to_s.split("/").last,
        "title" => fields.dig("title", "stringValue"),
        "date" => fields.dig("date", "timestampValue"),
        "startTime" => fields.dig("startTime", "stringValue"),
        "genre" => fields.dig("genre", "stringValue"),
        "isActive" => fields.dig("isActive", "booleanValue")
      }
    end
  end
end
