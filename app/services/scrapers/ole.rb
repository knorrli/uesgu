require 'nokogiri'

module Scrapers
  # OLE (Open Linked Event Data) — a single standardized XML schema that many
  # (Bern-weighted) Swiss venues expose. There is NO central API: each venue hosts
  # its own endpoint and hinto.ch/oleexport is just a registry of those URLs. One
  # adapter reads ANY OLE endpoint, so **a source is config, not code** — the
  # SOURCES list below drives a generated Agent subclass per feed (see the loop at
  # the bottom of this file), so adding a venue is a one-line entry, not a new
  # class file.
  #
  # Per-event schema (XML namespaces stripped):
  #
  #   <event source_id>
  #     <name> <url> <ticket_url> <lead> <description>
  #     <shows><show source_id><date_start>ISO-8601</date_start><date_end></show></shows>
  #     <categories><category>…</category></categories>
  #     <location><name><street><code>(PLZ)<locality></location>
  #   </event>
  #
  # Field mapping: name→title (squished, trailing ":" stripped), lead→subtitle
  # (only for events that have their own content — see #event_subtitle),
  # date_start→start_time, categories→consumption genres (they MINT taxonomy and
  # land in the curation queue — we collect everything and curate downstream, per
  # the taxonomy-hygiene model), location→event_locations. <description> is read
  # only as the "has own content" signal that gates the subtitle (it's full HTML
  # prose and there's no description column to store it in); <image> and <files>
  # are ignored — no image ingestion by design.
  #
  # IMPORTANT — the event URL is the venue's own <url>, never <ticket_url>.
  # <ticket_url> is usually the Eventfrog/PETZI mirror; pointing users there is the
  # exact mistake the PETZI scraper still has. We keep <url> (the real venue page)
  # as the canonical link and only *append the show date* to it to keep one
  # event's N shows as N distinct, stable upsert keys (Event keys on url).
  #
  # Overlap with PETZI/bespoke scrapers is expected (Dachstock is in all three)
  # and is resolved by Scrapers::Dedup, which matches on venue + date + fuzzy
  # title. OLE is the PREFERRED source there (venue-published, links to the real
  # venue page), so an overlapping PETZI/bespoke copy folds onto the OLE event,
  # not the other way round. (See dedup_test.rb for the proof.)
  class Ole < Agent
    # --- Source registry. A single-venue source declares its [venue, city,
    # canton] place and seeds the location taxonomy like a normal scraper. An
    # aggregator (multi-venue) declares `aggregator: true`; its venue is resolved
    # per event from <location> and it is kept OUT of the taxonomy (see #aggregator?
    # and Location.place_scrapers) — exactly like PETZI.
    #
    # This is the SHIPPING list: every feed here was dry-parsed live against the
    # real endpoint (script/ole_dry_parse.rb) and is robots-allowed + parses
    # clean. Adding a venue is a one-line entry — a source is config, not code.
    SOURCES = [
      # Dachstock is also in PETZI — included on purpose to prove Dedup absorbs the
      # overlap (venue + date + title) instead of duplicating it.
      { key: 'Dachstock',  feed_url: 'https://api.dachstock.ch/wp-json/ds/v1/hinto',
        location: ['Dachstock', 'Bern', 'BE'] },

      # Net-new, non-PETZI single-venue Bern feeds.
      # { key: 'Klangkeller', feed_url: 'https://www.klangkeller-bern.ch/app/klangkeller/action/oleexport',
      #   location: ['Klangkeller', 'Bern', 'BE'] },
      { key: 'LaCappella',  feed_url: 'https://www.la-cappella.ch/app/lacappella/action/oleexport',
        location: ['La Cappella', 'Bern', 'BE'] }
      # { key: 'CasinoBern',  feed_url: 'https://www.casinobern.ch/wp-content/themes/casinobern/views/component/event/ole/',
      #   location: ['Casino Bern', 'Bern', 'BE'] }
      # { key: 'Lichtspiel',  feed_url: 'https://www.lichtspiel.ch/oleexport/',
      #   location: ['Lichtspiel', 'Bern', 'BE'] },
      # { key: 'Stattland',   feed_url: 'https://stattland.ch/feed/ole',
      #   location: ['Stattland', 'Bern', 'BE'] }
    ].freeze

    # Configured + parseable but DEFERRED, for reference (NOT swept). Both return
    # Mechanize::RobotsDisallowedError: their OLE export endpoint is robots-
    # disallowed for our UA. We enforce robots (Agent#respect_robots) and treat
    # opting out as a deliberate per-venue decision (cf. Scrapers::BadBonn's
    # documented opt-out), not one to make unattended — so they wait for a human
    # robots call. NB: BeJazz was the intended aggregator proof; aggregator
    # support is implemented + covered by ole_test.rb regardless (see #aggregator?
    # / #locations_for). The messy aggregates (Konzerte Bern = 0 genres + address
    # in <name>; Hinto ALL = 46 venues) stay deferred too. See BACKLOG.
    DEFERRED = [
      { key: 'Birdseye', feed_url: 'https://www.birdseye.ch/HintoEventlist.php',
        location: ['Birdseye', 'Basel', 'BS'], reason: :robots },
      { key: 'BeJazz', feed_url: 'http://www.bejazz.ch/app/bejazz/action/oleexport/',
        aggregator: true, reason: :robots }
    ].freeze

    # One occurrence (event × show) carrying everything the field extractors need;
    # the event/show nodes plus the bits we resolved while expanding (start_time,
    # the venue-pointing url, the [venue, city, canton] tags).
    Row = Struct.new(:event, :show, :start_time, :url, :locations, keyword_init: true)

    # Pagination early-exit margin. Feeds dump full history (back to ~2012) over
    # dozens of slow pages; the shipping ones are ordered newest-first, so once
    # this many CONSECUTIVE pages yield no upcoming show, the rest is past-only and
    # we stop. The margin tolerates the feeds' not-quite-monotonic date order (a
    # later page can briefly poke back above today). See #event_rows.
    STOP_AFTER_EMPTY_PAGES = 3

    # Sources are generated subclasses (see bottom of file). They're created
    # anonymously via Class.new, so they have no name when Ruby fires `inherited`
    # — suppress Registerable's auto-registration here (no super) and register each
    # explicitly once it has been named + configured.
    def self.inherited(child)
      # deliberately NOT calling super — see note above.
    end

    class << self
      attr_accessor :feed_url, :place, :is_aggregator, :label, :provenance

      # Build (but do NOT register) a configured source subclass. The shipping
      # loop at the bottom of this file names + registers each; tests call this to
      # get an isolated single-venue / aggregator class without touching the live
      # registry, so coverage doesn't depend on which feeds are currently enabled.
      def build(key:, feed_url:, place: nil, aggregator: false)
        Class.new(self) do
          self.feed_url      = feed_url
          self.place         = place
          self.is_aggregator = aggregator
          self.label         = key
          self.provenance    = "OLE:#{key}"
        end
      end

      def url = URI.parse(feed_url)

      # Single-venue: the configured venue. Aggregator: a readable placeholder
      # (the real venue is resolved per event in #event_locations and this never
      # enters the taxonomy — see #aggregator?).
      def location = place ? place.first : label

      def locations = place || [location]

      def aggregator? = !!is_aggregator

      # Provenance stamped on every event (Event#data_source), e.g. "OLE:Klangkeller".
      def source_key = provenance
    end

    # --- Template-method hooks -------------------------------------------------

    # process_events fetched page 1 (get(self.class.url)); we parse it, follow
    # <meta><next_url> pagination, and expand every <event> into one Row per
    # upcoming <show>. Returning the fully-resolved Rows keeps the field extractors
    # trivial (they just read the Row).
    #
    # Stops early once STOP_AFTER_EMPTY_PAGES consecutive pages produce no upcoming
    # row — the past-only history tail of a newest-first feed. The `rows.any?`
    # guard keeps an oldest-first feed (whose upcoming events trail at the end)
    # paging until it reaches them, so the early-exit only ever skips real history,
    # never real events. `max_pages` remains the hard ceiling.
    def event_rows
      rows = []
      doc = current_doc
      pages = 1
      empty_streak = 0
      loop do
        page_rows = rows_from(doc)
        rows.concat(page_rows)

        empty_streak = page_rows.empty? ? empty_streak + 1 : 0
        break if rows.any? && empty_streak >= STOP_AFTER_EMPTY_PAGES

        nxt = next_url(doc)
        break if nxt.blank?

        cap = max_pages(doc)
        break if cap.positive? && pages >= cap

        get(nxt)
        doc = current_doc
        pages += 1
      end
      rows
    end

    def event_url(row) = row.url

    def event_start_time(row) = row.start_time

    # name → title, squished with any trailing ":" removed (OLE titles often read
    # "Artist:" with the lineup appended after the colon).
    def event_title(row) = clean_title(text(row.event, 'name'))

    # <lead> is the event's teaser line and makes a good subtitle — EXCEPT the
    # feed injects the generic VENUE blurb into <lead> for bare listings (club
    # nights etc.) that have no content of their own, which would then repeat the
    # same paragraph across most of a venue's events. Those content-less events
    # have an empty <description> (just a stray <br/>) while real events carry a
    # populated one, so we gate on it: keep <lead> only when the event actually
    # has a description. Drops the repeated venue blurb without losing real subtitles.
    def event_subtitle(row)
      return nil unless description_present?(row.event)

      plain_text(text(row.event, 'lead')).presence
    end

    # <categories> are consumption genres: they mint taxonomy (unrecognised tokens
    # land UNPLACED in the curation queue), so we keep every token and curate
    # downstream rather than gate at ingest.
    def event_consumption_genres(row)
      row.event.css('categories category').map { |c| squish(c.text) }.reject(&:blank?).uniq
    end

    def event_locations(row) = row.locations

    private

    # Parse the current page body as namespaced-stripped XML.
    def current_doc
      doc = Nokogiri::XML(page.body)
      doc.remove_namespaces!
      doc
    end

    # Expand each <event> into one Row per UPCOMING <show>. Two gotchas live here:
    # (1) feeds dump full history (back to 2012) → drop shows before today; (2) one
    # event with N shows becomes N events, each keyed on the venue url + its show
    # date so the upsert keys stay distinct.
    def rows_from(doc)
      doc.css('event').flat_map do |event_node|
        base_url = text(event_node, 'url')
        next [] if base_url.blank?

        locations = locations_for(event_node)
        event_node.css('shows show').filter_map do |show_node|
          start = parse_start(show_node)
          next if start.nil? || start.to_date < Date.current # drop past shows

          Row.new(event: event_node, show: show_node, start_time: start,
                  url: occurrence_url(base_url, start), locations: locations)
        end
      end
    end

    # ISO-8601 so no fuzzy parsing; a blank/garbled date is skipped with a warn
    # (like the Schüür parser) rather than aborting the feed.
    def parse_start(show_node)
      raw = text(show_node, 'date_start')
      return nil if raw.blank?

      Time.zone.parse(raw)
    rescue ArgumentError => e
      Rails.logger.warn("[#{self.class.location}] unparseable OLE date_start #{raw.inspect}: #{e.message}")
      nil
    end

    # The venue's own page (NOT <ticket_url>, which is the Eventfrog/PETZI mirror),
    # with the show date appended so one event's N shows stay distinct, stable
    # upsert keys. A fragment keeps the link pointing at the real venue page.
    def occurrence_url(base_url, start)
      "#{base_url}#show-#{start.to_date.iso8601}"
    end

    # Single-venue: the configured place. Aggregator: resolve per event from
    # <location>, deriving canton from the PLZ (the only canton signal OLE gives).
    def locations_for(event_node)
      return self.class.locations unless self.class.aggregator?

      loc    = event_node.at_css('location')
      venue  = clean_title(text(loc, 'name'))
      city   = squish(text(loc, 'locality'))
      canton = SwissPostcode.canton(text(loc, 'code'))
      [venue, city, canton].compact_blank.presence || self.class.locations
    end

    def text(node, css)
      node&.at_css(css)&.text
    end

    # True when <description> holds real text — i.e. anything survives once the
    # HTML scaffolding (<br/>, other tags, entities, whitespace) is stripped. A
    # bare listing's description is just "<br/>", which reads as blank here, so it
    # gates the venue-blurb <lead> out of the subtitle (see #event_subtitle).
    def description_present?(event_node)
      text(event_node, 'description').to_s
        .gsub(/<[^>]+>/, ' ')
        .gsub(/&[^;\s]+;/, ' ')
        .strip.present?
    end

    # <lead> is HTML-ish prose (entities like &amp;, the odd inline tag). Render it
    # to clean single-line plain text so it doesn't double-escape through the view's
    # simple_format (which would otherwise show a literal "&amp;").
    def plain_text(html) = squish(Nokogiri::HTML.fragment(html.to_s).text)

    def squish(str) = str.to_s.gsub(/\s+/, ' ').strip

    # Squish + drop a trailing colon ("Mardi Gras:" → "Mardi Gras").
    def clean_title(str) = squish(str).sub(/\s*:\z/, '')

    def next_url(doc) = squish(text(doc, 'meta next_url'))

    def max_pages(doc) = text(doc, 'meta max_pages').to_i
  end

  # The base registered itself via Agent.inherited (the `class Ole < Agent` keyword
  # names it before the hook runs) — drop it: it's abstract and must never sweep.
  All.scrapers.delete(Ole.name.demodulize)

  # Generate + name + register one Agent subclass per shipping source. Done here
  # (not via a file per venue) so a new feed is a SOURCES entry, not code.
  Ole::SOURCES.each do |src|
    const = "Ole#{src[:key]}"
    klass = Ole.build(key: src[:key], feed_url: src[:feed_url],
                      place: src[:location], aggregator: src.fetch(:aggregator, false))
    Scrapers.const_set(const, klass)
    All.scrapers[const] = klass
  end
end
