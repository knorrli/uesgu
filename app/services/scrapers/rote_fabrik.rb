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

    # The public event page is a Vue hash-route on the main site's programme — the
    # SPA's own JSON-LD declares it as `…/de/programm.html#/events/<id>`, keyed on
    # the OCCURRENCE id (top-level `id`), NOT `r_f_event_id`. The `kalender.` feed
    # host is a login-gated backend whose `/events/<id>` pages 404 to a visitor, and
    # `r_f_event_id` collides with an unrelated occurrence in the public route — so
    # both halves of the old URL were wrong (see event_url_pattern + the golden suite).
    def event_url(row)
      id = row['id']
      "https://rotefabrik.ch/de/programm.html#/events/#{id}" if id.present?
    end

    # The feed host (kalender.) ≠ the public event host, so pin the full public
    # shape rather than inheriting the host-from-feed default.
    def self.event_url_pattern
      %r{\Ahttps://rotefabrik\.ch/de/programm\.html#/events/\d+\z}
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
