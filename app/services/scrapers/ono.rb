module Scrapers
  # ONO (Das Kulturlokal, Bern) runs an EventON/WordPress calendar. Its listing
  # pages carry schema.org microdata per event (a clean ISO `startDate` with year
  # + offset, plus the canonical event URL and an `eventStatus`), so we read the
  # microdata rather than parsing German date text — no silent-today risk.
  #
  # ONO has no genre/style field, but it IS a multidisciplinary house: roughly half
  # its programme is non-music (literature readings, talks, dance & theatre). The
  # homepage lists everything with no category, which would ship all that non-music
  # into a music feed permanently visible (the music gate can only hide an event via
  # its genres). So instead of the homepage we walk ONO's own SECTION pages and tag
  # each event with the section it lives under (SOUNDS / JAZZ / KLASSIK / LITERATUR /
  # TANZ & THEATER / SPEZIAL). That closed vocabulary mints taxonomy the usual way:
  # Jazz/Klassik fingerprint-match existing music genres; Literatur / Tanz & Theater /
  # Spezial arrive unplaced for an admin to hide. Private events ("Privatanlass") are
  # excluded for free — they appear on the homepage but in no public section.
  class Ono < Agent
    # slug on onobern.ch => the section label we tag events with. Order matters only
    # in that the first section is fetched by the base `get(url)` (see #event_rows).
    # "literatur-2" really is ONO's SPEZIAL page — the CMS slug is just historical.
    SECTIONS = {
      "sounds" => "Sounds",
      "jazz-2" => "Jazz",
      "klassik-2" => "Klassik",
      "literatur" => "Literatur",
      "tanz-theater" => "Tanz & Theater",
      "literatur-2" => "Spezial"
    }.freeze

    def self.section_url(slug)
      URI.parse("https://www.onobern.ch/#{slug}/")
    end

    # The base fetches this first; we make it the first section so `page` is already
    # the SOUNDS listing when #event_rows runs (the rest are fetched there).
    def self.url
      section_url(SECTIONS.keys.first)
    end

    # Section pages carry no description prose; the short subtitle is our secondary
    # text (see #event_description). The genre is the ONO section, not a source field.
    field_gaps description: :no_field

    # Walk every section page, tagging each row with its section as the genre. The
    # base already fetched the first section into `page`; we `get` the remaining
    # five. A nil `get` (offline golden harness) ends enrichment after the fixture
    # section, keeping the golden deterministic — mirrors Le Singe's pagination.
    def event_rows
      first_slug, *rest = SECTIONS.keys
      rows = tag_rows(page, SECTIONS[first_slug])
      rest.each do |slug|
        resp = get(self.class.section_url(slug))
        break unless resp

        rows.concat(tag_rows(resp, SECTIONS[slug]))
      end
      rows
    end

    def event_url(content)
      content.at_css('[itemprop="url"]')&.attr("href").presence
    end

    # Microdata datetime — full date, time and year, e.g. "2026-7-25T15:00+2:00"
    # (months/days aren't zero-padded, but Time.zone.parse reads it fine).
    def event_start_time(content)
      date_string = content.at_css('meta[itemprop="startDate"]')&.attr("content")
      raise "Unparseable ONO date: #{date_string.inspect}" if date_string.blank?

      Time.zone.parse(date_string)
    end

    def event_title(content)
      content.at_css(".evcal_event_title")&.text&.squish
    end

    # A short curated descriptor sits under the title ("Konzert", "Contemporary
    # Celtic Strings", "Lesung mit eigenen Texten"). Our single secondary-text field.
    def event_description(content)
      content.at_css(".evcal_event_subtitle")&.text&.squish.presence
    end

    # The section this row was tagged with in #event_rows.
    def event_genres(content)
      Array(content["data-ono-genre"].presence)
    end

    # EventON exposes a dedicated schema.org status, so read it rather than scanning
    # the title for a cancellation word.
    def event_cancelled?(_event, content)
      content.at_css('meta[itemprop="eventStatus"]')&.attr("content").to_s.include?("EventCancelled")
    end

    private

    # Stamp each event row on a page with its section, so the (node-based) field
    # extractors can read the genre back off the node without a parallel lookup.
    def tag_rows(page, genre)
      page.search("#evcal_list .eventon_list_event").to_a.each do |row|
        row["data-ono-genre"] = genre
      end
    end
  end
end
