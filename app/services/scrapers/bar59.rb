module Scrapers
  # Bar 59 (Luzern) renders its events client-side from a public, read-only
  # Firebase Firestore collection; the served HTML is an empty Vue shell, so this
  # scraper reads the Firestore REST API. Rows are flattened Hashes.
  class Bar59 < Agent
    def self.location
      "Bar 59"
    end

    def self.locations
      [location, "Luzern", "LU"]
    end

    # The feed is on Firestore (see #url), so the venue domain isn't derivable from
    # url.host — declare it for the ledger drift test.
    def self.venue_domains = ["bar59.ch"]

    # Public web API key (same one the browser uses). The collection holds the full
    # history back to 2024 in document-id order, so we page through everything and
    # filter to active, upcoming events below.
    API_KEY = "AIzaSyDALptf6C6dG09tEfMdikBrMSAPPZqyHgk".freeze
    BASE = "https://firestore.googleapis.com/v1/projects/bar59-b8e95/databases/(default)/documents/events?key=#{API_KEY}&pageSize=300".freeze

    def self.url
      URI.parse(BASE)
    end

    # Bar 59's Firestore feed carries a genre field (extracted below) but no
    # description / secondary-title field.
    field_gaps description: :no_field

    def event_rows
      docs = all_documents
      docs.map { |doc| flatten(doc) }
          .select { |row| row["isActive"] && row["date"] && Date.parse(row["date"]) >= Date.current }
    end

    # No per-event detail page exists; the Firestore document id is the only stable
    # identifier, so key the event on a synthetic anchor URL built from it.
    def event_url(row)
      "https://www.bar59.ch/#event-#{row['id']}" if row["id"].present?
    end

    # The feed lives on a Firestore backend, so the public event host isn't the
    # feed host — pin it explicitly for the golden-suite URL assertion.
    def self.event_url_pattern
      %r{\Ahttps://www\.bar59\.ch/#event-}
    end

    # `date` is an ISO timestamp at midnight UTC (year present); the actual start is
    # the separate `startTime` string (e.g. "20:00").
    def event_start_time(row)
      date = row["date"].to_s[/\d{4}-\d{2}-\d{2}/]
      raise "Unparseable Bar 59 date: #{row['date'].inspect}" if date.blank?

      time = row["startTime"].to_s[/\d{1,2}:\d{2}/]
      Time.zone.parse("#{date} #{time}")
    end

    def event_title(row)
      row["title"].to_s.squish
    end

    # `genre` is a free-text, comma-separated string ("Salsa, Bachata, Reggaeton").
    # Unstable, but every token mints and is curated downstream.
    def event_genres(row)
      row["genre"].to_s.split(",").map(&:squish).compact_blank
    end

    private

    def all_documents
      # The base already fetched page 1 into `page`; start from it and follow
      # nextPageToken for the rest (a no-op when there's only one page).
      body = JSON.parse(page.body)
      docs = Array(body["documents"])
      token = body["nextPageToken"]
      while token.present? && (resp = get("#{BASE}&pageToken=#{token}"))
        body = JSON.parse(resp.body)
        docs.concat(Array(body["documents"]))
        token = body["nextPageToken"]
      end
      docs
    end

    # Firestore wraps every field in a typed object ({"stringValue": …}); pull the
    # values we need into a plain hash.
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
