module Scrapers
  # Café/Bar Mokka (Thun) runs WordPress, and its custom `event` post type is
  # exposed over the WP REST API with clean ACF fields — a machine `event_date`
  # (YYYYMMDD) and a start time — so we read JSON rather than the JS-hydrated agenda
  # that earned the old `js_only` write-off. Rows are plain Hashes; the extractors
  # read ACF keys instead of CSS.
  #
  # The API serves the FULL archive (5000+ events, newest-POSTED first) and offers
  # no server-side filter on the event date, so we page from the top and keep only
  # events dated today or later, stopping once a page carries no upcoming event
  # (upcoming ones cluster in the most-recently-posted pages). MAX_PAGES caps it.
  #
  # There is no genre/category taxonomy on the event type, and Mokka's programme
  # mixes the odd non-music night (quiz, kids, Kleinkunst) in among the concerts.
  # We can't gate those at ingest — there's no field to read — so we mine the
  # subtitle + body for known styles (match-only) and leave recurring non-music
  # formats to admin discard rules.
  class Mokka < Agent
    field_gaps genres: :no_field

    PER_PAGE = 100
    MAX_PAGES = 6

    def self.endpoint(page)
      URI.parse("https://mokka.ch/wp-json/wp/v2/events?per_page=#{PER_PAGE}&page=#{page}")
    end

    def self.url
      endpoint(1)
    end

    # The base fetched page 1; keep paging until a page has no upcoming event (or the
    # cap). A nil `get` (offline golden harness) ends paging after the fixture page.
    def event_rows
      rows = upcoming_from(page.body)
      page_num = 2
      while page_num <= MAX_PAGES && (resp = get(self.class.endpoint(page_num)))
        batch = upcoming_from(resp.body)
        break if batch.empty?

        rows.concat(batch)
        page_num += 1
      end
      rows
    end

    def event_url(row)
      row["link"].presence
    end

    # ACF `event_date` is "YYYYMMDD"; `event_start` is "HH.MM Uhr" (dot separator).
    # Fall back to the doors time (`event_opening`) if a start time is ever missing.
    def event_start_time(row)
      date = row.dig("acf", "event_date").to_s
      raise "Unparseable Mokka date: #{date.inspect}" unless date.match?(/\A\d{8}\z/)

      time = time_of(row, "event_start") || time_of(row, "event_opening")
      Time.zone.parse("#{date[0, 4]}-#{date[4, 2]}-#{date[6, 2]} #{time}")
    end

    def event_title(row)
      decode(row.dig("title", "rendered"))
    end

    # The subtitle is the venue's own one-line descriptor ("100% DRUM'N'BASS ALL
    # NIGHT LONG…") — our secondary text.
    def event_description(row)
      decode(row.dig("acf", "event_subtitle")).presence
    end

    # No genre field, but the subtitle + the WYSIWYG body blocks name real styles —
    # mine the known ones (match-only; mints nothing).
    def event_genre_prose(row)
      blocks = Array(row.dig("acf", "elements")).map { |el| el["wysiwyg"] }
      html = [row.dig("acf", "event_subtitle"), *blocks].compact.join("\n")
      decode(html.gsub(/<[^>]+>/, " "))
    end

    # The ACF `event_state` badge occasionally carries a cancellation word; read it
    # on top of the base title/description scan.
    def event_cancelled?(event, row)
      super || CANCELLATION_MARKER.match?(row.dig("acf", "event_state").to_s)
    end

    private

    def upcoming_from(body)
      Array(parse_json(body)).select do |e|
        date = e.dig("acf", "event_date").to_s
        date.match?(/\A\d{8}\z/) && (Date.strptime(date, "%Y%m%d") >= Date.current)
      end
    end

    def time_of(row, key)
      row.dig("acf", key).to_s[/\d{1,2}[.:]\d{2}/]&.tr(".", ":")
    end

    def decode(html)
      CGI.unescapeHTML(html.to_s).squish
    end
  end
end
