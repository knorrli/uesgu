require 'nokogiri'

module Scrapers
  # PETZI (petzi.ch) is the Swiss federation of music venues; its agenda is the
  # shared ticketing/listing backend for many of our venues, so its data is clean
  # and uniform. Unlike every other scraper this one is MULTI-VENUE: the sitemap
  # enumerates every event across all members, each detail page is server-rendered
  # (no JS), and the venue is resolved per event from the URL slug.
  #
  # We consume only the 14 venues we already track, so PETZI can be merged against
  # our bespoke scrapers (see Scrapers::Dedup). PETZI is the *primary* (stable)
  # source; the bespoke scrapers fill the events PETZI omits. Genres here are
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

    def self.url
      URI.parse('https://www.petzi.ch/en/sitemap.xml')
    end

    def self.location
      'PETZI'
    end

    def self.locations
      [location] # fallback only; real value comes per-event from #event_locations
    end

    # The sitemap lists every member event; keep only the URLs for venues we track.
    def event_rows
      xml = Nokogiri::XML(page.body)
      xml.remove_namespaces!
      xml.css('loc').map(&:text).select { |u| u.include?('/events/') && venue_for(u) }
    end

    def event_url(row) = row

    # Each row is an event URL; fetch its server-rendered detail page. Wrapped by
    # build_event's `transact`, so Mechanize history returns to the sitemap after.
    def event_content(row)
      get(row)
    end

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

    def venue_for(url)
      slug = VENUES.keys.find { |s| url =~ %r{/events/\d+-#{Regexp.escape(s)}-} }
      VENUES[slug]
    end
  end
end
