module Scrapers
  # Rote Fabrik (Zürich) is multidisciplinary; its calendar is a Vue SPA backed by
  # a clean public JSON API. The `?categories=konzert` feed returns only concerts,
  # keyed by event id. Rows are Hashes.
  class RoteFabrik < Agent
    def self.location
      'Rote Fabrik'
    end

    def self.locations
      [location, 'Zürich', 'ZH']
    end

    def self.url
      URI.parse('https://kalender.rotefabrik.ch/api/events?categories=konzert')
    end

    # The feed is a dict keyed by event id; each value is one occurrence carrying a
    # nested `rf_event`.
    def event_rows
      body = parse_json(page.body, default: {})
      body.is_a?(Hash) ? body.values : Array(body)
    end

    # No scrapable per-event page (the SPA route 404s to a plain GET), so key the
    # event on the calendar's canonical event URL.
    def event_url(row)
      id = row['r_f_event_id'] || row['id']
      "https://kalender.rotefabrik.ch/events/#{id}" if id.present?
    end

    # Top-level `date` is "YYYY-MM-DD HH:MM:SS" (year present); the real start is
    # the `from` (or door) "HH:MM:SS" time.
    def event_start_time(row)
      date = row['date'].to_s[/\d{4}-\d{2}-\d{2}/]
      raise "Unparseable Rote Fabrik date: #{row['date'].inspect}" if date.blank?

      time = (row['from'].presence || row['door']).to_s[/\d{1,2}:\d{2}/]
      Time.zone.parse("#{date} #{time}")
    end

    def event_title(row)
      row.dig('rf_event', 'title').to_s.squish
    end

    def event_subtitle(row)
      row.dig('rf_event', 'subtitle').to_s.squish.presence
    end

    # Fine genre facet (`tags`, a structured {id,name,slug} field) — clean by
    # construction, so allowed to mint taxonomy (discovery). Empty for current
    # concerts, so this is dormant until they populate it.
    def event_genres(row)
      Array(row.dig('rf_event', 'tags')).map { |t| (t.is_a?(Hash) ? t['name'] : t).to_s.squish }.compact_blank
    end
  end
end
