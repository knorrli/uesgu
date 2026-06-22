require 'test_helper'

# Focused parser test for the generic OLE adapter. The shared golden harness
# assumes one HTML list page per venue; OLE is XML + pagination + one-event-to-
# many-shows + per-event aggregator locations, none of which that harness models,
# so OLE gets its own fixtures + asserts (same call as Petzi/Schüür).
#
# Fixtures + taxonomy are synthetic (project-test-synthetic-taxonomy): invented
# venue, artist and genre names, never real catalogue content.
class Scrapers::OleTest < Minitest::Test
  FIXTURES = File.expand_path('../../fixtures/scrapers/ole', __dir__)
  # Pin "today" so the date filter is deterministic regardless of when the suite
  # runs (same device as the golden harness's REFERENCE_DATE).
  TODAY = Date.new(2026, 6, 10)

  # Isolated source classes built from the SAME factory the shipping loop uses,
  # so the parser is tested independently of which live feeds are currently
  # enabled (e.g. the only aggregator, BeJazz, is deferred for robots reasons).
  def single_venue
    Scrapers::Ole.build(key: 'Klangkeller', feed_url: 'https://venue.example/oleexport',
                        place: ['Klangkeller', 'Bern', 'BE'])
  end

  def aggregator
    Scrapers::Ole.build(key: 'TestAgg', feed_url: 'https://agg.example/oleexport', aggregator: true)
  end

  # An editorial aggregator that keys + links on the per-event <source_url>
  # instead of the venue homepage <url> (Bewegungsmelder-shaped).
  def source_aggregator
    Scrapers::Ole.build(key: 'TestSrc', feed_url: 'https://bm.example/oleexport',
                        aggregator: true, link_via: :source)
  end

  # --- single-venue: pagination + date filter + multi-show + URL rule ---------

  def test_single_venue_paginates_filters_and_expands
    events = run_offline(single_venue, 'single_page1.xml', 'single_page2.xml')

    # A (1 future show; its 2020 show dropped) + B (2 future shows) + C (page 2).
    # "Has Been Trio" (all-past) contributes nothing. Wibble Trio appearing at all
    # proves page 2 was fetched (pagination), not just page 1.
    assert_equal ['Zorptron Quartet', 'Glorptet', 'Glorptet', 'Wibble Trio'],
                 events.map(&:title)

    refute(events.any? { |e| e.title == 'Has Been Trio' }, 'an all-past event must be dropped entirely')
  end

  # Newest-first feeds dump full history behind the upcoming events; stop once
  # STOP_AFTER_EMPTY_PAGES consecutive pages yield no upcoming row so we don't
  # page through years of past-only events. (Real feeds: 25 pages → ~8.)
  def test_pagination_stops_after_consecutive_past_only_pages
    events = run_offline(single_venue,
                         'paginate_future.xml',
                         'paginate_empty.xml', 'paginate_empty.xml', 'paginate_empty.xml',
                         'paginate_unreached.xml')
    titles = events.map(&:title)
    assert_includes titles, 'Reachable Act'
    refute_includes titles, 'Unreachable Act',
                     'must bail after the past-only tail, never reaching the 5th page'
  end

  # Safety for oldest-first feeds: leading past-only pages must NOT trip the
  # early-exit — we've collected nothing yet, so the rows.any? guard keeps paging
  # until the upcoming events at the tail.
  def test_pagination_keeps_going_through_leading_past_pages
    events = run_offline(single_venue,
                         'paginate_empty.xml', 'paginate_empty.xml', 'paginate_empty.xml',
                         'paginate_tail.xml')
    assert_includes events.map(&:title), 'Tail Act',
                    'oldest-first feeds must page through to their upcoming events'
  end

  def test_trailing_colon_stripped_and_lead_becomes_description_when_described
    events = run_offline(single_venue, 'single_page1.xml', 'single_page2.xml')
    by_title = events.index_by(&:title)

    a = by_title['Zorptron Quartet']
    assert_equal 'Zorptron Quartet', a.title           # source had "Zorptron Quartet:"
    # <lead>, kept because the event has a <description>; HTML entity decoded.
    assert_equal 'with Blip & Collective', a.description
  end

  # The description gate: an event whose <description> is just a stray <br/> is a
  # bare listing, so its <lead> is the generic venue blurb and must be dropped.
  def test_lead_dropped_when_description_is_empty
    events = run_offline(single_venue, 'single_page1.xml', 'single_page2.xml')
    wibble = events.find { |e| e.title == 'Wibble Trio' }
    assert_nil wibble.description, 'no real <description> → venue-blurb <lead> is gated out'
  end

  def test_past_shows_are_dropped_but_future_kept
    a = run_offline(single_venue, 'single_page1.xml', 'single_page2.xml').first
    # Only the 2026-07-01 show survives the 2020-01-15 drop.
    assert_equal '2026-07-01 20:30', a.start_time.strftime('%Y-%m-%d %H:%M')
    assert_equal Date.new(2026, 7, 1), a.start_date
  end

  def test_multi_show_event_yields_distinct_venue_urls
    events = run_offline(single_venue, 'single_page1.xml', 'single_page2.xml')
    glorptet = events.select { |e| e.title == 'Glorptet' }

    assert_equal 2, glorptet.size, 'one event with two shows → two events'
    assert_equal %w[https://venue.example/events/b#show-2026-08-10
                    https://venue.example/events/b#show-2026-08-11].sort,
                 glorptet.map(&:url).sort
    assert_equal 2, glorptet.map(&:url).uniq.size, 'upsert keys must be distinct'
  end

  def test_event_url_is_the_venue_not_the_ticket_mirror
    events = run_offline(single_venue, 'single_page1.xml', 'single_page2.xml')
    # <ticket_url> points at eventfrog.ch — it must never become the event URL.
    refute(events.any? { |e| e.url.include?('eventfrog') },
           'the canonical URL must be the venue <url>, never the <ticket_url> mirror')
    assert(events.all? { |e| e.url.start_with?('https://venue.example/') })
  end

  def test_single_venue_uses_configured_place_and_categories
    a = run_offline(single_venue, 'single_page1.xml', 'single_page2.xml').first
    assert_equal ['Klangkeller', 'Bern', 'BE'], a.location_list
    assert_equal %w[Zorpjazz Bliptronica], a.genre_list
    assert_equal 'OLE:Klangkeller', a.data_source
  end

  # --- aggregator: per-event location + PLZ→canton ---------------------------

  def test_aggregator_resolves_location_and_canton_from_plz
    events = run_offline(aggregator, 'aggregator.xml')
    by_title = events.index_by(&:title)

    # 3011 → BE, 3920 → VS (deliberately non-Bern, proving it isn't hard-wired).
    assert_equal ['Marians Jazzroom', 'Bern', 'BE'], by_title['Snarftet plays Florp'].location_list
    assert_equal ['Vernissage Halle', 'Zermatt', 'VS'], by_title['Bergglorp Ensemble'].location_list
  end

  # --- link_via: :source — key + link on <source_url>, not the venue homepage --

  # Two different events at the SAME venue homepage on the SAME night: keying on
  # <url>+date would collide them into one, so the per-event <source_url> is the
  # only safe upsert key. Also proves the HTML char-ref in the URL is decoded.
  def test_source_linked_aggregator_keys_on_decoded_source_url
    events = run_offline(source_aggregator, 'source_keyed.xml')

    glorptron = events.find { |e| e.title == 'Glorptron Live' }
    assert_equal 'https://bm.example/?post_type=event&p=100#show-2026-07-20', glorptron.url,
                 '&#038; must be decoded to & and the show date appended'
    refute(events.any? { |e| e.url.start_with?('https://kulturhof.example') },
           'the venue homepage <url> must not be the key when link_via: :source')
    assert_equal events.size, events.map(&:url).uniq.size,
                 'same-venue/same-night events must get distinct keys via <source_url>'
  end

  # A multi-show event still gets one distinct key per show (source_url + date).
  def test_source_linked_multi_show_keys_stay_distinct
    events = run_offline(source_aggregator, 'source_keyed.xml')
    snarf = events.select { |e| e.title == 'Snarfwave' }
    assert_equal %w[https://bm.example/?post_type=event&p=200#show-2026-07-20
                    https://bm.example/?post_type=event&p=200#show-2026-07-21].sort,
                 snarf.map(&:url).sort
  end

  # When the aggregator's <url> IS a genuine per-event deep link, link there
  # (the venue) rather than the aggregator's own <source_url>.
  def test_source_linked_prefers_a_real_venue_deep_link_over_source_url
    events = run_offline(source_aggregator, 'source_keyed.xml')
    florp = events.find { |e| e.title == 'Florpcore Festival' }
    assert_equal 'https://dieheiterefahne.example/events/1257/15#show-2026-07-25', florp.url,
                 'a digit-bearing venue deep link is preferred over <source_url>'
  end

  # A category shipping "&amp;" literally inside its CDATA must be entity-decoded,
  # not minted as the junk genre "Speis &Amp; Trank".
  def test_category_html_entities_are_decoded
    events = run_offline(source_aggregator, 'source_keyed.xml')
    florp = events.find { |e| e.title == 'Florpcore Festival' }
    assert_includes florp.genre_list, 'Speis & Trank'
    refute(florp.genre_list.any? { |g| g.include?('amp;') }, 'no raw HTML entity may leak into a genre')
  end

  # A city the feed mis-tags via a wrong PLZ is corrected to its real canton
  # (Wabern → BE, not VS as PLZ 3984/Fiesch would resolve).
  def test_city_canton_fix_overrides_a_wrong_plz
    s = aggregator.new
    node = Nokogiri::XML(<<~XML).remove_namespaces!.at_css('event')
      <event><url>https://x.example/e</url>
        <shows><show><date_start>2026-07-01T20:00:00+02:00</date_start></show></shows>
        <location><name>Heitere Fahne</name><code>3984</code><locality>Wabern</locality></location>
      </event>
    XML
    assert_equal ['Heitere Fahne', 'Wabern', 'BE'], s.send(:locations_for, node)
  end

  # --- unit-level guards on the cleanup helpers ------------------------------

  def test_clean_title_strips_trailing_colon_and_squishes
    s = single_venue.new
    assert_equal 'Mardi Gras', s.send(:clean_title, '  Mardi   Gras :  ')
    assert_equal 'Plain Title', s.send(:clean_title, 'Plain Title')
  end

  def test_occurrence_url_appends_show_date_to_venue_url
    s = single_venue.new
    url = s.send(:occurrence_url, 'https://x.example/y', Time.zone.parse('2026-07-01T20:30:00+02:00'))
    assert_equal 'https://x.example/y#show-2026-07-01', url
  end

  private

  # Drive #process_events fully offline. `get` serves the next fixture page from a
  # queue (so following <meta><next_url> just pops page 2), `page` returns the
  # current one, and the DB-touching genre/visibility derivation is no-op'd —
  # exactly the seams the golden + Schüür harnesses stub.
  Capture = Struct.new(:url) do
    def new_record? = true
    def id = nil
    def dismissed? = false
    def overridden?(_field) = false
    def save! = nil
    attr_accessor :start_time, :start_date, :title, :description,
                  :genre_list, :location_list, :cancelled_at, :rescheduled_at,
                  :hidden, :data_source
  end

  def run_offline(klass, *fixture_files)
    queue = fixture_files.map { |f| page_from(f) }
    current = { page: nil }
    captured = []
    factory = ->(*, **kwargs) { Capture.new(kwargs[:url]).tap { |c| captured << c } }

    scraper = klass.new
    scraper.define_singleton_method(:get) { |*| current[:page] = queue.shift }
    scraper.define_singleton_method(:page) { current[:page] }
    scraper.define_singleton_method(:ensure_genres_and_visibility) { |event| }

    Date.stub(:current, TODAY) do
      Event.stub(:find_or_initialize_by, factory) do
        scraper.send(:process_events)
      end
    end
    captured
  end

  def page_from(file)
    Mechanize::Page.new(
      URI('https://venue.example/oleexport'),
      { 'content-type' => 'application/xml; charset=utf-8' },
      File.binread(File.join(FIXTURES, file)), '200', Mechanize.new
    )
  end
end
