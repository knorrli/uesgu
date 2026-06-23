require "test_helper"

# Focused unit test for the multi-venue PETZI scraper. The shared golden harness
# assumes a single venue + DOM-link click-into-detail, neither of which fits PETZI
# (multi-venue, sitemap → fetch-by-URL), so PETZI gets its own fixtures + asserts.
class Scrapers::PetziTest < Minitest::Test
  FIXTURES = File.expand_path("../../fixtures/scrapers/petzi", __dir__)
  DETAIL_URL = "https://www.petzi.ch/en/events/61806-kulturfabrik-kofmehl-malevolence/".freeze

  def page_from(name, uri, ctype)
    Mechanize::Page.new(URI(uri), { "content-type" => ctype },
                        File.binread(File.join(FIXTURES, name)), "200", Mechanize.new)
  end

  def page_from_html(html, uri)
    Mechanize::Page.new(URI(uri), { "content-type" => "text/html; charset=utf-8" },
                        html, "200", Mechanize.new)
  end

  # Prime the per-row detail-page cache so event_url reads it without a live fetch
  # (event_url fetches the detail page itself in production; the field-extractor
  # tests above pass the page in directly).
  def scraper_on(page, row: DETAIL_URL)
    scraper(current_row: row).tap do |s|
      s.instance_variable_set(:@detail_row, row)
      s.instance_variable_set(:@detail_page, page)
    end
  end

  def detail = @detail ||= page_from("detail.html", DETAIL_URL, "text/html; charset=utf-8")

  def scraper(current_row: DETAIL_URL)
    Scrapers::Petzi.new.tap { |s| s.instance_variable_set(:@current_row, current_row) }
  end

  def test_event_rows_keeps_only_tracked_venue_events
    s = Scrapers::Petzi.new
    sitemap = page_from("sitemap.xml", Scrapers::Petzi.url.to_s, "application/xml; charset=utf-8")
    s.define_singleton_method(:page) { sitemap }

    rows = s.event_rows
    # kofmehl + kiff are tracked; belluard (untracked venue) and the /locations/
    # page are dropped.
    assert_equal 2, rows.size
    assert(rows.any? { |u| u.include?("kulturfabrik-kofmehl") })
    assert(rows.any? { |u| u.include?("-kiff-") })
    refute(rows.any? { |u| u.include?("belluard") })
    refute(rows.any? { |u| u.include?("/locations/") })
  end

  def test_extracts_title
    assert_equal "Malevolence", scraper.event_title(detail)
  end

  def test_extracts_show_time_not_doors
    # detail page shows "Doors open at: 18:00" and "Event starts at: 18:45"
    t = scraper.event_start_time(detail)
    assert_equal [2026, 6, 17, 18, 45], [t.year, t.month, t.day, t.hour, t.min]
  end

  def test_extracts_curated_genre_tags
    assert_equal %w[Concert Rock], scraper.event_genres(detail)
  end

  def test_resolves_venue_location_from_url_slug
    assert_equal ["Kofmehl", "Solothurn", "SO"], scraper.event_locations(detail)
  end

  def test_url_is_the_venue_official_website
    # The Kofmehl detail fixture carries an "official website" link on the venue's
    # own domain (kofmehl.net) — event_url prefers it over the petzi.ch URL.
    assert_equal "https://kofmehl.net/programm/malevolence/",
                 scraper_on(detail).event_url(DETAIL_URL)
  end

  def test_url_falls_back_to_petzi_when_no_venue_link
    # No link on the venue's domain (only an off-domain/petzi link) → keep the
    # petzi.ch URL. Dedup then ranks this copy last anyway.
    bare = page_from_html('<html><body><a href="https://www.petzi.ch/x">x</a></body></html>', DETAIL_URL)
    assert_equal DETAIL_URL, scraper_on(bare).event_url(DETAIL_URL)
  end
end
