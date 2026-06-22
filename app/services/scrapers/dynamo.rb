require 'cgi'

module Scrapers
  # Jugendkulturhaus Dynamo (Zürich) runs a Next.js front-end over a headless
  # Drupal/NodeHive JSON:API. We query upcoming events server-side, keep the ones
  # tagged as concerts, and map the finer category tags to genres. Rows are Hashes.
  class Dynamo < Agent
    def self.location
      'Dynamo'
    end

    def self.locations
      [location, 'Zürich', 'ZH']
    end

    # The feed is on the NodeHive backend (see #url), so the venue domain isn't
    # derivable from url.host — declare it for the ledger drift test.
    def self.venue_domains = ['dynamo.ch']

    # The "Konzert" category marks an event as a concert; the rest of the term ids
    # are genre facets we surface as genres (they mint and are curated downstream).
    CONCERT_TID = 20
    GENRE_BY_TID = {
      14 => 'Metal', 15 => 'Hip-Hop', 16 => 'Elektro',
      17 => 'Hardcore/Punk', 18 => 'Pop', 32 => 'Rock/Indie'
    }.freeze

    def self.url
      params = {
        'filter[field_event_date.value][operator]' => '>',
        'filter[field_event_date.value][value]' => Date.current.iso8601,
        'sort' => 'field_event_date.value',
        'page[limit]' => '50'
      }
      query = params.map { |k, v| "#{CGI.escape(k)}=#{CGI.escape(v)}" }.join('&')
      URI.parse("https://dynamo.nodehive.app/jsonapi/node/event?#{query}")
    end

    # Dynamo's feed carries a genre taxonomy (extracted below) but no subtitle
    # field.
    field_gaps subtitle: :no_field

    def event_rows
      Array(parse_json(page.body, default: {})['data'])
    end

    # Drop courses/markets/workshops; keep only concert-tagged events.
    def skip_row?(row)
      category_tids(row).exclude?(CONCERT_TID)
    end

    def event_url(row)
      alias_path = row.dig('attributes', 'path', 'alias')
      "https://www.dynamo.ch#{alias_path}" if alias_path.present?
    end

    # The feed is a NodeHive backend, so the public event host isn't the feed host
    # — pin it explicitly for the golden-suite URL assertion.
    def self.event_url_pattern
      %r{\Ahttps://www\.dynamo\.ch/}
    end

    # `field_event_date.value` is full ISO 8601 with offset and year — clean.
    def event_start_time(row)
      value = row.dig('attributes', 'field_event_date', 'value')
      raise "Missing Dynamo date for #{event_url(row)}" if value.blank?

      Time.zone.parse(value)
    end

    # `attributes.title` appends a "- DD.MM.YYYY" suffix; `field_title` is clean.
    def event_title(row)
      row.dig('attributes', 'field_title').to_s.squish
    end

    # Genres come from a fixed Drupal taxonomy (stable term ids → known names) — a
    # clean structured source, so allowed to mint taxonomy (discovery).
    def event_genres(row)
      category_tids(row).filter_map { |tid| GENRE_BY_TID[tid] }
    end

    private

    def category_tids(row)
      Array(row.dig('relationships', 'field_categories', 'data'))
        .filter_map { |term| term.dig('meta', 'drupal_internal__target_id') }
    end
  end
end
