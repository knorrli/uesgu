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

  def test_trailing_colon_stripped_and_lead_becomes_subtitle_when_described
    events = run_offline(single_venue, 'single_page1.xml', 'single_page2.xml')
    by_title = events.index_by(&:title)

    a = by_title['Zorptron Quartet']
    assert_equal 'Zorptron Quartet', a.title           # source had "Zorptron Quartet:"
    # <lead>, kept because the event has a <description>; HTML entity decoded.
    assert_equal 'with Blip & Collective', a.subtitle
  end

  # The subtitle gate: an event whose <description> is just a stray <br/> is a
  # bare listing, so its <lead> is the generic venue blurb and must be dropped.
  def test_lead_dropped_when_description_is_empty
    events = run_offline(single_venue, 'single_page1.xml', 'single_page2.xml')
    wibble = events.find { |e| e.title == 'Wibble Trio' }
    assert_nil wibble.subtitle, 'no real <description> → venue-blurb <lead> is gated out'
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
    attr_accessor :start_time, :start_date, :title, :subtitle,
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
