require "nokogiri"
require "cgi"

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
  # Field mapping: name→title (squished, trailing ":" stripped), lead→description
  # (only for events that have their own content — see #event_description),
  # date_start→start_time, categories→genres (they MINT taxonomy and
  # land in the curation queue — we collect everything and curate downstream, per
  # the taxonomy-hygiene model), location→event_locations. <description> is read
  # only as the "has own content" signal that gates the description (it's full HTML
  # prose and there's no description column to store it in); <image> and <files>
  # are ignored — no image ingestion by design.
  #
  # IMPORTANT — the event URL is the venue's own <url>, never <ticket_url>.
  # <ticket_url> is usually the Eventfrog/PETZI mirror; pointing users there is a
  # mistake the PETZI scraper used to make (it now prefers the venue's official-
  # website link, see Scrapers::Petzi#event_url). We keep <url> (the real venue page)
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
    # canton] place; its venue lives in the registry (config/venues.yml) and seeds
    # the location taxonomy like any consume venue. An aggregator (multi-venue)
    # declares `aggregator: true`; its venue is resolved per event from <location>,
    # and only an APPROVED venue (a registry row, possibly aggregator-sourced) enters
    # the taxonomy — the aggregator feed host itself is placeless and excluded.
    #
    # This is the SHIPPING list: every feed here was dry-parsed live against the
    # real endpoint (script/ole_dry_parse.rb) and is robots-allowed + parses
    # clean. Adding a venue is a one-line entry — a source is config, not code.
    SOURCES = [
      # Dachstock is also in PETZI — included on purpose to prove Dedup absorbs the
      # overlap (venue + date + title) instead of duplicating it.
      { key: "Dachstock",  feed_url: "https://api.dachstock.ch/wp-json/ds/v1/hinto",
        location: ["Dachstock", "Bern", "BE"] },

      # Net-new, non-PETZI single-venue Bern feeds.
      # { key: 'Klangkeller', feed_url: 'https://www.klangkeller-bern.ch/app/klangkeller/action/oleexport',
      #   location: ['Klangkeller', 'Bern', 'BE'] },
      # La Cappella dropped: it's a Kleinkunst/cabaret house, not a music venue —
      # its feed is ~80% Kabarett & Comedy / Theater / Mundart / Worte / Zauberkunst,
      # which clashes with our music focus and would flood the taxonomy. (Also an
      # oldest-first feed, so it walks its full history every sweep, and it acts as
      # an organiser — events it promotes at other venues we scrape would duplicate
      # under a "La Cappella" tag that dedup can't merge.)
      # { key: 'LaCappella',  feed_url: 'https://www.la-cappella.ch/app/lacappella/action/oleexport',
      #   location: ['La Cappella', 'Bern', 'BE'] },
      # CasinoBern dropped: only ever exposed a 2019 dataset, never updated since.
      # { key: 'CasinoBern',  feed_url: 'https://www.casinobern.ch/wp-content/themes/casinobern/views/component/event/ole/',
      #   location: ['Casino Bern', 'Bern', 'BE'] }
      # { key: 'Lichtspiel',  feed_url: 'https://www.lichtspiel.ch/oleexport/',
      #   location: ['Lichtspiel', 'Bern', 'BE'] },
      # { key: 'Stattland',   feed_url: 'https://stattland.ch/feed/ole',
      #   location: ['Stattland', 'Bern', 'BE'] }

      # Bewegungsmelder — a Bern-region editorial culture AGGREGATOR (robots-OK;
      # ~7600 events / 152 pages, newest-first). Two things make it different from
      # the single-venue feeds above and drive the two non-default flags:
      #   aggregator: true  — venue is resolved per event from <location> (+PLZ→
      #                       canton), and it stays OUT of the location taxonomy.
      #   link_via: :source — its <url> is unreliable: a real per-event deep link
      #                       for some venues, but a bare homepage (identical per
      #                       event, can't be a key) for most. We PREFER the venue
      #                       deep link when present, else fall back to the stable
      #                       per-event <source_url> — never the homepage (see
      #                       #event_base_url / #venue_event_link?). (The
      #                       <ticket_url> eventfrog mirror is never used, so
      #                       eventfrog-republished rows need no special handling
      #                       — see FINDINGS-bewegungsmelder.md.)
      # Heavy overlap with venues we already consume (Bee-Flat, Dachstock,
      # Dampfzentrale, Dynamo, Turnhalle, Rote Fabrik, …) is folded by Scrapers::
      # Dedup. ~Half the programme is non-music (Theater/Party/Tanz/…); the music
      # gate hides it via db/genres.yml dispositions (curated, not gated at ingest).
      # gate: :strict (the default, stated for visibility) — only registry-approved
      # venues ingest; the rest are recorded as VenueLead leads for review. Both
      # surfaced venues (Heitere Fahne, Kulturhof Schloss Köniz) are approved, so
      # strict drops nothing today. Flip to :lenient to ingest unapproved venues too.
      { key: "Bewegungsmelder", feed_url: "https://bewegungsmelder.ch/oleexport/",
        aggregator: true, link_via: :source, gate: :strict }
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
      { key: "Birdseye", feed_url: "https://www.birdseye.ch/HintoEventlist.php",
        location: ["Birdseye", "Basel", "BS"], reason: :robots },
      { key: "BeJazz", feed_url: "http://www.bejazz.ch/app/bejazz/action/oleexport/",
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
      attr_accessor :feed_url, :place, :is_aggregator, :label, :provenance, :link_via, :gate

      # The aggregator ingest gate (closed allowlist): :strict (default) ingests
      # events only for venues approved in the registry and DROPS the rest; :lenient
      # ingests everything. Either way every unapproved venue is recorded as a
      # discovery lead (VenueLead). Single-venue sources are never gated.
      def strict? = gate != :lenient

      # Build (but do NOT register) a configured source subclass. The shipping
      # loop at the bottom of this file names + registers each; tests call this to
      # get an isolated single-venue / aggregator class without touching the live
      # registry, so coverage doesn't depend on which feeds are currently enabled.
      #
      # link_via selects which feed field is the event's canonical link + upsert
      # key (see #event_base_url): the default :venue uses the venue's own <url>;
      # :source uses the per-event <source_url>. Editorial AGGREGATORS (e.g.
      # Bewegungsmelder) expose only a venue *homepage* in <url> — same for every
      # event there, so <url>+date collides for two same-night shows at one venue —
      # while <source_url> is a stable, rich, per-event page on the aggregator. For
      # those, :source is both the only safe key AND the better user link.
      def build(key:, feed_url:, place: nil, aggregator: false, link_via: :venue, gate: :strict)
        Class.new(self) do
          self.feed_url      = feed_url
          self.place         = place
          self.is_aggregator = aggregator
          self.label         = key
          self.provenance    = "OLE:#{key}"
          self.link_via      = link_via
          self.gate          = gate
        end
      end

      def url = URI.parse(feed_url)

      # Single-venue: the configured venue. Aggregator: a readable placeholder
      # (the real venue is resolved per event in #event_locations and this never
      # enters the taxonomy — see #aggregator?).
      def location = place ? place.first : label

      def locations = place || [location]

      def aggregator? = !!is_aggregator

      # The domain(s) reconciled against the registry's `consume` rows (see the drift
      # test). Agent returns [] for any aggregator, because a member-enumerating
      # one (Petzi) commits to no single host. An OLE aggregator is different: it's
      # ONE fixed feed endpoint, so the domain we commit to scraping IS that feed
      # host — it takes a single `consume` row, even though it still resolves the
      # actual VENUE per event (#aggregator? keeps it out of the location taxonomy).
      # Single-venue OLE sources already got this from Agent; we just opt
      # aggregators back in so the registry can record the decision.
      #
      # An aggregator ALSO covers the approved venues that name it as their source
      # (`sources: [{ via: ole, aggregator: <label> }]` in config/venues.yml) — those
      # venues have no own-domain scraper, so the aggregator is what backs their
      # `consume` row. Including them here is what lets the drift test reconcile an
      # aggregator-sourced venue (e.g. Heitere Fahne via Bewegungsmelder) cleanly.
      def venue_domains
        own = [Discovery.domain(url.host)].compact
        return own unless aggregator?

        own + Venue.all.select { |v| v.consume? && v.aggregator_names.include?(label) }.map(&:domain)
      end

      # Provenance stamped on every event (Event#data_source), e.g. "OLE:Klangkeller".
      def source_key = provenance
    end

    # Real sweep entry point. After the base run (fetch → build → save events),
    # record the discovery leads this aggregator surfaced (VenueLead) — the venues it
    # resolved that aren't approved in the registry. Only #call does this; the
    # golden/OLE offline tests drive #process_events directly and the dry parse calls
    # #event_rows, so neither writes VenueLead rows. A no-op for single-venue sources.
    def call
      result = super
      persist_leads
      result
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
    def event_title(row) = clean_title(text(row.event, "name"))

    # <lead> is the event's teaser line and makes a good description — EXCEPT the
    # feed injects the generic VENUE blurb into <lead> for bare listings (club
    # nights etc.) that have no content of their own, which would then repeat the
    # same paragraph across most of a venue's events. Those content-less events
    # have an empty <description> (just a stray <br/>) while real events carry a
    # populated one, so we gate on it: keep <lead> only when the event actually
    # has a description. Drops the repeated venue blurb without losing real descriptions.
    def event_description(row)
      return nil unless description_present?(row.event)

      plain_text(text(row.event, "lead")).presence
    end

    # <categories> mint taxonomy (unrecognised tokens land UNPLACED in the curation
    # queue), so we keep every token and curate downstream rather than gate at ingest.
    def event_genres(row)
      row.event.css("categories category").map { |c| squish(decode(c.text)) }.reject(&:blank?).uniq
    end

    def event_locations(row) = row.locations

    # Closed-allowlist gate: an aggregator ingests an event only if its resolved
    # venue is a CONSUME venue in the registry. A venue we've rejected/deferred — or
    # never seen — is dropped under the default :strict gate (kept under :lenient).
    # An unseen venue is also recorded as a lead (#persist_leads); a rejected one is
    # not (already triaged). Single-venue sources declare an approved place, so they
    # are never gated.
    def skip_row?(row)
      return false unless self.class.aggregator?
      return false if Venue.matching(row.locations.first)&.consume?

      self.class.strict?
    end

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
      doc.css("event").flat_map do |event_node|
        base_url = event_base_url(event_node)
        next [] if base_url.blank?

        locations = locations_for(event_node)
        rows = event_node.css("shows show").filter_map do |show_node|
          start = parse_start(show_node)
          next if start.nil? || start.to_date < Date.current # drop past shows

          Row.new(event: event_node, show: show_node, start_time: start,
                  url: occurrence_url(base_url, start), locations: locations)
        end
        # Remember an aggregator's resolved place once we know it has an upcoming
        # show, so Location can fold the venue into the WHERE tree (see #call →
        # #persist_discovered_places). In-memory only — never writes here, so the
        # read-only dry parse (which calls #event_rows, not #call) stays read-only.
        note_place(locations, rows.size) if rows.any?
        rows
      end
    end

    # This event's canonical link + upsert key (occurrence_url then appends the
    # show date to keep N shows distinct). CGI.unescapeHTML undoes the HTML
    # char-refs these feeds bake into a URL inside CDATA (e.g. "&#038;" → "&");
    # it's a no-op on the already-clean URLs of the single-venue sources.
    #
    # Default (link_via: :venue): the venue's own <url> — NEVER the <ticket_url>
    # mirror (see the class comment).
    #
    # Editorial aggregator (link_via: :source, e.g. Bewegungsmelder): its <url> is
    # unreliable — for some venues it's a real per-event deep link, for most it's
    # just a bare homepage (identical for every event there, so it can't be a key).
    # We PREFER the venue's own page when <url> is a genuine event-specific deep
    # link (see #venue_event_link?), since linking users to the venue beats the
    # aggregator; otherwise we fall back to the per-event <source_url> (the
    # aggregator's own event page) — never the useless, collision-prone homepage.
    def event_base_url(event_node)
      venue = decode(text(event_node, "url"))
      return venue unless self.class.link_via == :source

      venue_event_link?(venue) ? venue : decode(text(event_node, "source_url")).presence
    end

    def decode(raw) = raw.blank? ? raw : CGI.unescapeHTML(raw)

    # A venue <url> worth linking to over the aggregator: a real per-event deep
    # link, not a bare homepage or a generic section page. Conservative on purpose
    # — the feed's <url> is junky (homepages, a "/menu" page) and a wrong guess
    # would collide two events onto one key. We trust it only when the path carries
    # a digit/id segment or there's a query string; bare domains and word-only
    # section pages (/menu) fall through to the stable per-event <source_url>.
    def venue_event_link?(url)
      return false if url.blank?

      uri = URI.parse(url)
      return true if uri.query.present?

      uri.path.to_s.split("/").any? { |seg| seg.match?(/\d/) }
    rescue URI::InvalidURIError
      false
    end

    # ISO-8601 so no fuzzy parsing; a blank/garbled date is skipped with a warn
    # (like the Schüür parser) rather than aborting the feed.
    def parse_start(show_node)
      raw = text(show_node, "date_start")
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

    # Manual canton corrections for cities an aggregator mis-tags via a wrong PLZ.
    # The only canton signal OLE gives is the PLZ, so a typo'd code resolves to the
    # wrong canton (Bewegungsmelder lists Wabern bei Köniz under 3984 = Fiesch/VS;
    # its real PLZ is 3084/BE). Keyed on the downcased locality, so it corrects the
    # specific place without remapping a PLZ that's legitimately VS for elsewhere.
    # Add a row when a venue lands in the wrong canton in the WHERE tree.
    CITY_CANTON_FIXES = { "wabern" => "BE" }.freeze

    # Single-venue: the configured place. Aggregator: resolve per event from
    # <location>, deriving canton from the PLZ (the only canton signal OLE gives),
    # with CITY_CANTON_FIXES overriding known upstream PLZ typos.
    def locations_for(event_node)
      return self.class.locations unless self.class.aggregator?

      loc    = event_node.at_css("location")
      venue  = clean_title(text(loc, "name"))
      city   = squish(text(loc, "locality"))
      canton = CITY_CANTON_FIXES[city.downcase] || SwissPostcode.canton(text(loc, "code"))
      [venue, city, canton].compact_blank.presence || self.class.locations
    end

    # Tally an aggregator's resolved [venue, city, canton] tuples and their upcoming-
    # event counts during the run; persisted later by #persist_leads. Only
    # aggregators need this — single-venue sources declare an approved place. Skip a
    # tuple too thin to place (no city).
    def note_place(locations, count)
      return unless self.class.aggregator? && locations.size >= 2

      (@discovered_places ||= Hash.new(0))[locations] += count
    end

    # Record the discovery LEADS this run surfaced: resolved venues that match NO
    # approved venue in the registry (the approved ones are ingested, not leads),
    # with their upcoming-event count for ranking. Rewritten fresh per source, so an
    # approved or aged-out venue drops off the inbox. (Was persist_discovered_places,
    # which fed the taxonomy; that now reads the registry — see VenueLead.)
    def persist_leads
      return unless self.class.aggregator?

      leads = (@discovered_places || {}).filter_map do |(venue, city, canton), count|
        next if Venue.matching(venue)

        { venue: venue, city: city, canton: canton, event_count: count }
      end
      VenueLead.refresh!(source: self.class.source_key, leads: leads)
    end

    def text(node, css)
      node&.at_css(css)&.text
    end

    # True when <description> holds real text — i.e. anything survives once the
    # HTML scaffolding (<br/>, other tags, entities, whitespace) is stripped. A
    # bare listing's description is just "<br/>", which reads as blank here, so it
    # gates the venue-blurb <lead> out of the description (see #event_description).
    def description_present?(event_node)
      text(event_node, "description").to_s
        .gsub(/<[^>]+>/, " ")
        .gsub(/&[^;\s]+;/, " ")
        .strip.present?
    end

    # <lead> is HTML-ish prose (entities like &amp;, the odd inline tag). Render it
    # to clean single-line plain text so it doesn't double-escape through the view's
    # simple_format (which would otherwise show a literal "&amp;").
    def plain_text(html) = squish(Nokogiri::HTML.fragment(html.to_s).text)

    def squish(str) = str.to_s.gsub(/\s+/, " ").strip

    # Decode HTML char-refs + squish + drop a trailing colon ("Mardi Gras:" →
    # "Mardi Gras"). The decode handles feeds that ship "&amp;" literally inside a
    # CDATA title or venue name ("Speis &amp; Trank" → "Speis & Trank"), matching
    # how <lead> is already entity-decoded in #plain_text.
    def clean_title(str) = squish(decode(str)).sub(/\s*:\z/, "")

    def next_url(doc) = squish(text(doc, "meta next_url"))

    def max_pages(doc) = text(doc, "meta max_pages").to_i
  end

  # The base registered itself via Agent.inherited (the `class Ole < Agent` keyword
  # names it before the hook runs) — drop it: it's abstract and must never sweep.
  All.scrapers.delete(Ole.name.demodulize)

  # Generate + name + register one Agent subclass per shipping source. Done here
  # (not via a file per venue) so a new feed is a SOURCES entry, not code.
  Ole::SOURCES.each do |src|
    const = "Ole#{src[:key]}"
    klass = Ole.build(key: src[:key], feed_url: src[:feed_url],
                      place: src[:location], aggregator: src.fetch(:aggregator, false),
                      link_via: src.fetch(:link_via, :venue), gate: src.fetch(:gate, :strict))
    Scrapers.const_set(const, klass)
    All.scrapers[const] = klass
  end
end
