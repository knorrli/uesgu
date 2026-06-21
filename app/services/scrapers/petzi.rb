require 'nokogiri'

module Scrapers
  # PETZI (petzi.ch) is the Swiss federation of music venues; its agenda is the
  # shared ticketing/listing backend for many of our venues, so its data is clean
  # and uniform. Unlike every other scraper this one is MULTI-VENUE: the sitemap
  # enumerates every event across all members, each detail page is server-rendered
  # (no JS), and the venue is resolved per event from the URL slug.
  #
  # We consume only the 14 venues we already track, so PETZI can be merged against
  # our bespoke/OLE scrapers (see Scrapers::Dedup). PETZI links to the venue's OWN
  # event page when the detail page exposes an "official website" link (see
  # #event_url), otherwise to its own ticketing page — so Dedup ranks it LAST and
  # it's the visible copy only for shows no other source covers. Genres here are
  # consumption (match-only): the venue tags are curated but coarse, so they enrich
  # but never mint taxonomy.
  class Petzi < Agent
    # slug (the leading venue segment of /events/{id}-{slug}-{title}) => the exact
    # [venue, city, canton] our bespoke scrapers already declare, so a merged event
    # keeps one consistent location and dedup matches by venue.
    VENUES = {
      'dachstock'            => ['Dachstock', 'Bern', 'BE'],
      'isc'                  => ['ISC', 'Bern', 'BE'],
      'cafe-kairo'           => ['Café Kairo', 'Bern', 'BE'],
      'gaskessel'            => ['Gaskessel', 'Bern', 'BE'],
      'kulturfabrik-kofmehl' => ['Kofmehl', 'Solothurn', 'SO'],
      'fri-son'              => ['FriSon', 'Fribourg', 'FR'],
      'sedel'                => ['Sedel', 'Luzern', 'LU'],
      'nouveau-monde'        => ['Nouveau Monde', 'Fribourg', 'FR'],
      'helsinki'             => ['Helsinki Klub', 'Zürich', 'ZH'],
      'docks'                => ['Docks', 'Lausanne', 'VD'],
      'treibhaus'            => ['Treibhaus', 'Luzern', 'LU'],
      'neubad'               => ['Neubad', 'Luzern', 'LU'],
      'kiff'                 => ['KIFF', 'Aarau', 'AG'],
      'borom'                => ['Böröm', 'Aarau', 'AG']
    }.freeze

    # slug => the venue's canonical domain (eTLD+1), so this aggregator can declare
    # which venues it covers for the ledger drift test (Petzi adds no new venue —
    # every slug also has a bespoke scraper, so these match those scrapers' domains
    # and fold onto the same consume row). Kept parallel to VENUES; the drift test
    # asserts the two key sets stay aligned.
    DOMAINS = {
      'dachstock'            => 'dachstock.ch',
      'isc'                  => 'isc-club.ch',
      'cafe-kairo'           => 'cafe-kairo.ch',
      'gaskessel'            => 'gaskessel.ch',
      'kulturfabrik-kofmehl' => 'kofmehl.net',
      'fri-son'              => 'fri-son.ch',
      'sedel'                => 'sedel.ch',
      'nouveau-monde'        => 'nouveaumonde.ch',
      'helsinki'             => 'helsinkiklub.ch',
      'docks'                => 'docks.ch',
      'treibhaus'            => 'treibhausluzern.ch',
      'neubad'               => 'neubad.org',
      'kiff'                 => 'kiff.ch',
      'borom'                => 'boeroem.ch'
    }.freeze

    # Multi-venue but statically enumerable: the 14 venue domains it covers.
    def self.venue_domains = DOMAINS.values

    def self.url
      URI.parse('https://www.petzi.ch/en/sitemap.xml')
    end

    def self.location
      'PETZI'
    end

    def self.locations
      [location] # fallback only; real value comes per-event from #event_locations
    end

    # Multi-venue: the venue is resolved per event (#event_locations), so the
    # class-level place above is a placeholder. Keeps "PETZI" out of the location
    # taxonomy / favorites hierarchy — the real venues come from their own scrapers.
    def self.aggregator?
      true
    end

    # The sitemap lists every member event; keep only the URLs for venues we track.
    def event_rows
      xml = Nokogiri::XML(page.body)
      xml.remove_namespaces!
      xml.css('loc').map(&:text).select { |u| u.include?('/events/') && venue_for(u) }
    end

    # The canonical link is the venue's OWN event page. PETZI exposes it on the
    # detail page as the optional "official website" link (the lone external,
    # non-social <a>); we use it only when it resolves to the venue's known domain
    # (Petzi::DOMAINS) — never an artist/promoter site a venue may have entered
    # there instead — and fall back to the PETZI URL when it's absent or off-domain.
    # So a PETZI-only show still points at the venue where it can; where we also
    # scrape the venue bespoke/OLE, Dedup ranks PETZI last and hides this copy.
    def event_url(row) = venue_url(detail_page(row), row) || row

    # The field extractors read the same detail page event_url already fetched
    # (memoized per row), so it's one request per event. Wrapped by build_event's
    # `transact`, so Mechanize history is restored after.
    def event_content(row) = detail_page(row)

    # Date from the <title> bar ("… / DD.MM.YYYY / Venue - City / PETZI"), clock
    # time from the body ("Event starts at: HH:MM", falling back to doors).
    def event_start_time(content)
      date = title_parts(content).find { |p| p =~ %r{\A\d{2}\.\d{2}\.\d{4}\z} }
      raise "Unparseable PETZI date for #{current_row}" if date.blank?

      d, m, y = date.split('.').map(&:to_i)
      hour, minute = show_or_doors(content)
      Time.zone.local(y, m, d, hour, minute)
    end

    def event_title(content)
      squish(content.parser.at_css('h1')&.text)
    end

    # Curated venue tags ("Concert", "Rock", "Hip-Hop"). Consumption (match-only):
    # type tags like "Concert"/"Festival" simply find no genre match and drop out.
    def event_consumption_genres(content)
      content.parser.css('a.tag').map { |a| squish(a.text) }.reject(&:blank?).uniq
    end

    # Multi-venue: resolve from the row (URL) currently being processed.
    def event_locations(_content)
      venue_for(current_row)
    end

    private

    def squish(str) = str.to_s.gsub(/\s+/, ' ').strip

    def title_parts(content)
      squish(content.parser.at_css('title')&.text).split(' / ')
    end

    # Prefer the show time; fall back to doors; then midnight if neither is shown.
    def show_or_doors(content)
      body = squish(content.parser.text)
      time = body[/Event starts at:\s*(\d{1,2})[:.](\d{2})/i, 0] ||
             body[/Doors open at:\s*(\d{1,2})[:.](\d{2})/i, 0]
      return [0, 0] unless time

      m = time.match(/(\d{1,2})[:.](\d{2})/)
      [m[1].to_i, m[2].to_i]
    end

    # The detail page, fetched once per row and shared by event_url + the field
    # extractors. event_url runs first in the template, so it primes the cache.
    def detail_page(row)
      if @detail_row != row
        @detail_row  = row
        @detail_page = get(row)
      end
      @detail_page
    end

    # The detail page's "official website" link iff it resolves to this venue's
    # known domain; nil otherwise (absent, or an off-domain artist/promoter link).
    def venue_url(page, row)
      domain = Petzi::DOMAINS[slug_for(row)]
      return if domain.blank?

      page.links.filter_map(&:href)
          .find { |href| href.start_with?('http') && Scrapers::Discovery.domain(href) == domain }
    end

    def slug_for(url)
      VENUES.keys.find { |s| url =~ %r{/events/\d+-#{Regexp.escape(s)}-} }
    end

    def venue_for(url) = VENUES[slug_for(url)]
  end
end
