module Scrapers
  # Marians Jazzroom (Bern) runs a Squarespace Events Collection. The programme
  # list (/termine-marians) server-renders every event as an `.eventlist-event`
  # article carrying an `--upcoming`/`--past` modifier and a machine date; we read
  # the upcoming rows and click into each detail page, which ships a clean
  # schema.org Event JSON-LD (ISO `startDate` with time, year and offset). We
  # deliberately DON'T touch the Squarespace `?format=json` / `?format=ical`
  # endpoints — robots.txt disallows them for our UA (only the bare pages are
  # allowed), which is what earned the venue its old `js_only` write-off.
  #
  # It's a jazz club, so every act is jazz (or jazz-adjacent blues/soul/funk):
  # we tag Jazz as the base genre — which keeps the venue music-visible — and mine
  # the detail blurb for any more specific styles it names (match-only).
  class Marians < Agent
    def self.url
      URI.parse("https://www.mariansjazzroom.ch/termine-marians")
    end

    # Only upcoming rows — Squarespace marks past events `--past`, so we never mint
    # the archive. TBA slots (see #skip_row?) are dropped on top of that.
    def event_rows
      page.css(".eventlist-event--upcoming")
    end

    # Unannounced dates render as an "Informationen folgen!" placeholder (auto-slug,
    # no lineup, no real detail page) — skip until the act is announced.
    def skip_row?(row)
      title = row_title(row)
      title.blank? || title.match?(/Informationen folgen/i)
    end

    def event_url(row)
      link = row.at_css("a.eventlist-title-link, a.eventlist-column-thumbnail")
      return if link.nil?

      URI.join(self.class.url, link.attr("href")).to_s
    end

    def event_content(row)
      click(Page::Link.new(row.at_css("a.eventlist-title-link"), @mech, page))
    end

    # The detail page's schema.org Event JSON-LD — clean ISO datetime (date, time,
    # year, offset), no German text parsing.
    def event_start_time(content)
      Time.zone.parse(event_ld(content).fetch("startDate"))
    end

    # JSON-LD name is "<Act> — Marians Jazzroom"; drop the venue suffix.
    def event_title(content)
      event_ld(content)["name"].to_s.sub(/\s*[—–-]\s*Marians Jazzroom\z/, "").strip
    end

    # The editorial tagline (first heading of the event body) is the secondary text;
    # the paragraphs below it are the lineup/bio.
    def event_description(content)
      content.at_css(".eventitem-column-content h2")&.text&.squish.presence
    end

    # Jazz club → Jazz is the base tag (keeps it music-visible); the base then adds
    # any more specific styles the blurb names.
    def event_genres(_content)
      ["Jazz"]
    end

    def event_genre_prose(content)
      content.at_css(".eventitem-column-content")&.text
    end

    private

    def row_title(row)
      row.at_css(".eventlist-title-link")&.text.to_s.strip
    end

    # The event's schema.org node from the detail page's JSON-LD (Squarespace also
    # emits WebSite + LocalBusiness blocks, so pick the Event). A detail page without
    # one is a real breakage — raise so it surfaces as a per-event failure.
    def event_ld(content)
      node = content.css('script[type="application/ld+json"]')
                    .map { |s| JSON.parse(s.text) rescue nil }
                    .compact.find { |d| d["@type"] == "Event" }
      node || raise("No Event JSON-LD on #{content.uri}")
    end
  end
end
