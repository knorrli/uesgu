require 'cgi'

module Scrapers
  # Südpol (Luzern/Kriens) serves its events from a headless-WordPress REST API;
  # the rendered site is a Nuxt SPA. The /wp/v2/events endpoint exposes the
  # category taxonomy, so we can filter to music (the house also programmes
  # theatre/dance). Rows are WP post Hashes.
  class Suedpol < Agent
    def self.location
      'Südpol'
    end

    def self.locations
      [location, 'Kriens', 'LU']
    end

    # Music category term ids: Konzert=4, Club=13, Sound=63.
    def self.endpoint(page)
      URI.parse("https://cms.sudpol.ch/?rest_route=/wp/v2/events&categories=4,13,63&per_page=100&page=#{page}")
    end

    def self.url
      endpoint(1)
    end

    # WP can only order by POST date, not by the ACF event date, so the endpoint
    # mixes years of history — page through all music events and keep the upcoming
    # ones (filtered on the ACF timestamp). The base already fetched page 1.
    def event_rows
      events = data_from(page.body)
      total = page.response['x-wp-totalpages'].to_i
      (2..total).each { |p| events.concat(data_from(get(self.class.endpoint(p)).body)) }
      events.select { |row| upcoming?(row) }
    end

    def event_url(row)
      row['link'].presence
    end

    # The feed is served from the cms. host, but `link` points at the public www.
    # host — pin it explicitly for the golden-suite URL assertion.
    def self.event_url_pattern
      %r{\Ahttps://www\.sudpol\.ch/}
    end

    # ACF `event_date_info` is an array of date rows (multi-date runs); take the
    # first. `event_date` is a UNIX timestamp that already carries the start time.
    def event_start_time(row)
      stamp = event_stamp(row)
      raise "Missing Südpol date for #{event_url(row)}" if stamp.blank?

      Time.zone.at(stamp.to_i)
    end

    def event_title(row)
      CGI.unescapeHTML(row.dig('title', 'rendered').to_s).squish
    end

    def event_description(row)
      CGI.unescapeHTML(row.dig('acf', 'subtitle').to_s).squish.presence
    end

    # ACF `tags` is an optional, free-text genre field; tokens mint and are
    # curated downstream.
    def event_genres(row)
      tags = row.dig('acf', 'tags')
      list = tags.is_a?(Array) ? tags : tags.to_s.split(',')
      list.map { |t| t.to_s.squish }.compact_blank
    end

    private

    def data_from(body)
      parse_json(body)
    end

    def event_stamp(row)
      Array(row.dig('acf', 'event_date_info')).first&.dig('event_date')
    end

    def upcoming?(row)
      stamp = event_stamp(row)
      stamp.present? && Time.zone.at(stamp.to_i).to_date >= Date.current
    end
  end
end
