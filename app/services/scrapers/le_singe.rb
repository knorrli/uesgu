module Scrapers
  # Le Singe (Biel/Bienne) is run by the KartellCulturel collective; its public
  # `getEvents` JSON endpoint serves clean structured events (ISO dates with year,
  # curated genre arrays), so this scraper reads JSON rather than HTML. Rows are
  # plain Hashes — the field extractors read keys instead of CSS.
  class LeSinge < Agent
    def self.location
      'Le Singe'
    end

    # Biel/Bienne is in canton Bern.
    def self.locations
      [location, 'Biel', 'BE']
    end

    # location=1 is Le Singe. The endpoint pages by `offset` in steps of 10.
    def self.endpoint(offset)
      URI.parse("https://kartellculturel.ch/getEvents?startDate=#{Date.current.iso8601}&lang=de&offset=#{offset}&location=1")
    end

    def self.url
      endpoint(0)
    end

    # The base fetched offset 0; keep requesting further offsets until a page comes
    # back empty.
    def event_rows
      events = data_from(page.body)
      offset = 10
      while (batch = data_from(get(self.class.endpoint(offset)).body)).any?
        events.concat(batch)
        offset += 10
      end
      events
    end

    def event_url(row)
      row['detailUrl'].presence
    end

    # startDate is a clean "YYYY-MM-DD HH:MM:SS" (year present); startTime is the
    # real door/show time in "HHhMM" form (e.g. "17h00").
    def event_start_time(row)
      date = row['startDate'].to_s[/\d{4}-\d{2}-\d{2}/]
      raise "Unparseable Le Singe date: #{row['startDate'].inspect}" if date.blank?

      time = row['startTime'].to_s.tr('h', ':')[/\d{1,2}:\d{2}/]
      Time.zone.parse("#{date} #{time}")
    end

    def event_title(row)
      row['nameBand'].presence || row['title']
    end

    def event_subtitle(row)
      row['subTitle'].presence
    end

    # The endpoint's `genres` is a curated, closed vocabulary maintained by the
    # collective (with stable numeric genreIds) — a clean structured field, so it
    # is allowed to mint taxonomy (discovery).
    def event_genres(row)
      Array(row['genres']).map { |g| g.to_s.squish }.compact_blank
    end

    def event_cancelled?(_event, row)
      row['isCancelled'] == true
    end

    private

    def data_from(body)
      JSON.parse(body).fetch('data', [])
    rescue JSON::ParserError
      []
    end
  end
end
