require 'cgi'
require 'nokogiri'

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
      parse_json(page.body)
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

    # billboard-byline is free-text HTML. Its <br> tags separate the tagline from
    # the support act (and some samples have no spaces around them), so promote
    # those to a middot first or strip_tags would merge the words; then strip every
    # remaining tag and decode entities (&amp; → &), matching event_title.
    def event_subtitle(row)
      html = event_field(row, 'billboard-byline').to_s.gsub(%r{<br\s*/?>}i, ' · ')
      CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(html)).squish.presence
    end


    # Free-text genre fields the venue types per event — match-only against the
    # existing vocabulary so typos/marketing terms can't mint taxonomy.
    # `musicradar` is a rich HTML blurb (Wer:/Stil:/Aktuell:/…); only its "Stil:"
    # line is genre data, so parse that segment out rather than the whole prose.
    def event_consumption_genres(row)
      extract_tag_genres(row) | extract_musicradar_genres(row)
    end

    private

    def event_field(row, key)
      row.dig('toolset-meta', 'eventzusatz', key, 'raw')
    end

    def artist_field(row, key)
      row.dig('toolset-meta', 'artistfields', key, 'raw').to_s.squish
    end

    # beschreibungstag-1 sometimes carries real genre info and sometimes a
    # type/location note ("Externer Anlass", "Girlhood") that DOES match vocabulary
    # and leaks onto events — kept in deliberately; the noise is pruned via the
    # admin queue rather than dropped here. beschreibungstag-2/3 are clean genre tags.
    def extract_tag_genres(row)
      %w[beschreibungstag-1 beschreibungstag-2 beschreibungstag-3].filter_map do |key|
        artist_field(row, key).presence
      end
    end

    # Walk the DOM from the <strong>Stil:</strong> label to the next <strong>, so
    # the surrounding marketing HTML (data-* attrs, decorative <strong>, <br>)
    # can't derail it.
    def extract_musicradar_genres(row)
      doc   = Nokogiri::HTML.fragment(artist_field(row, 'musicradar'))
      label = doc.css('strong').find { |s| s.text.squish =~ /\AStil:?\z/i }
      return [] unless label

      parts, node = [], label.next_sibling
      while node && !(node.element? && node.name == 'strong')
        parts << node.text if node.text?
        node = node.next_sibling
      end
      parts.join(' ').split(%r{[,/]}).map(&:squish).reject(&:blank?)
    end
  end
end
