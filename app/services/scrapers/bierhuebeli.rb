require 'cgi'

module Scrapers
  # Bierhübeli (Bern) runs on WordPress + Toolset; its public site is a paginated
  # Elementor view, but the WP REST API exposes the `event` post type cleanly. Each
  # row is a Hash. The Toolset custom field `eventzusatz.datum` is a Unix timestamp
  # whose UTC rendering is the show's Swiss wall-clock start (doors live alongside),
  # and the genre tags sit in free-text `beschreibungstag` fields.
  class Bierhuebeli < Agent
    # Ordered by publish date (newest first); 100 comfortably covers the upcoming
    # programme. Rows are JSON, so `page.body` is parsed, not the DOM.
    def self.url
      URI.parse('https://bierhuebeli.ch/wp-json/wp/v2/event?per_page=100')
    end

    def self.location
      'Bierhübeli'
    end

    def self.locations
      [location, 'Bern', 'BE']
    end

    def event_rows
      JSON.parse(page.body)
    rescue JSON::ParserError
      []
    end

    # Skip rows with no event date (drafts / mis-entered events).
    def skip_row?(row)
      event_field(row, 'datum').blank?
    end

    def event_url(row)
      row['link'].to_s
    end

    # `datum` is a Unix timestamp whose UTC rendering already reads as the local
    # Swiss wall-clock show time (verified against the separate doors time), so map
    # those Y/M/D h:m straight onto the zone — never apply the epoch's UTC offset.
    def event_start_time(row)
      stamp = event_field(row, 'datum')
      raise "Unparseable Bierhübeli date: #{stamp.inspect}" if stamp.blank?

      t = Time.at(stamp.to_i).utc
      Time.zone.local(t.year, t.month, t.day, t.hour, t.min)
    end

    def event_title(row)
      CGI.unescapeHTML(row.dig('title', 'rendered').to_s).squish
    end

    # Free-text genre fields the venue types per event — match-only against the
    # existing vocabulary so typos/marketing terms can't mint taxonomy.
    # beschreibungstag-1 is a type/location note ("Externer Anlass"), not a genre.
    def event_consumption_genres(row)
      %w[beschreibungstag-2 beschreibungstag-3].filter_map do |key|
        artist_field(row, key).presence
      end
    end

    private

    def event_field(row, key)
      row.dig('toolset-meta', 'eventzusatz', key, 'raw')
    end

    def artist_field(row, key)
      row.dig('toolset-meta', 'artistfields', key, 'raw').to_s.squish
    end
  end
end
