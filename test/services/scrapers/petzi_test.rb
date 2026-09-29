require "test_helper"

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

  def test_event_rows_keeps_only_tracked_venue_events_once_each
    s = Scrapers::Petzi.new
    sitemap = page_from("sitemap.xml", Scrapers::Petzi.url.to_s, "application/xml; charset=utf-8")
    s.define_singleton_method(:page) { sitemap }

    rows = s.event_rows
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
    t = scraper.event_start_time(detail)
    assert_equal [2026, 6, 17, 18, 45], [t.year, t.month, t.day, t.hour, t.min]
  end

  def titled(date) = page_from_html("<html><head><title>Festival / #{date} / KiFF - Aarau / PETZI</title></head></html>", DETAIL_URL)

  def test_date_range_starts_on_its_first_day
    t = scraper.event_start_time(titled("25.11-28.11.2026"))
    assert_equal [2026, 11, 25], [t.year, t.month, t.day]
  end

  def test_date_range_across_new_year_starts_in_the_earlier_year
    t = scraper.event_start_time(titled("01.10-13.05.2027"))
    assert_equal [2026, 10, 1], [t.year, t.month, t.day]
  end

  def test_date_without_a_year_is_unparseable
    assert_raises(RuntimeError) { scraper.event_start_time(titled("16-18.10")) }
  end

  def test_extracts_curated_genre_tags
    assert_equal %w[Concert Rock], scraper.event_genres(detail)
  end

  def described(text_block)
    page_from_html("<html><body><h1>Malevolence</h1><div class='events__details'><p class='text_block'>#{text_block}</p></div></body></html>", DETAIL_URL)
  end

  def test_description_is_the_leading_support_line
    assert_equal "Mit Drain, Gridiron", scraper.event_description(detail)
  end

  def test_description_skips_fri_son_ticket_prices
    fri_son = page_from("fri_son_detail.html", DETAIL_URL, "text/html; charset=utf-8")
    assert_equal "Soundsystem meeting\nReggae, Roots, Dub, Steppa", scraper.event_description(fri_son)
  end

  def test_description_prefers_a_support_paragraph_and_lists_it_on_one_line
    page = described("Geht es noch extremer?<br><br>Ein langer Text.<br><br>Special guests:<br>Servant (DE)<br>Spere (DE)")
    assert_equal "Special guests: Servant (DE), Spere (DE)", scraper.event_description(page)
  end

  def test_description_is_nil_when_the_text_opens_with_a_blurb
    assert_nil scraper.event_description(described("#{'Lange Prosa über die Band. ' * 10}<br><br>Mehr Prosa."))
  end

  def test_description_is_nil_for_a_multi_line_info_block
    assert_nil scraper.event_description(described("Quentin Sauvé<br>+ Léa Martinez<br>Indie Folk<br>Salle de spectacle"))
  end

  def test_description_drops_door_times_and_prices
    page = described("Türöffnung: 20:00 Uhr<br>Eintritt: CHF 25.00<br><br>Die Ü40-Party!")
    assert_equal "Die Ü40-Party!", scraper.event_description(page)
  end

  def test_description_is_nil_when_it_repeats_the_title
    assert_nil scraper.event_description(described("MALEVOLENCE"))
  end

  def test_description_reads_unicode_styled_letters_as_plain_text
    assert_equal "Folk, Jazz", scraper.event_description(described("𝐅𝐨𝐥𝐤, 𝐉𝐚𝐳𝐳"))
  end

  def test_resolves_venue_location_from_url_slug
    assert_equal ["Kofmehl", "Solothurn", "SO"], scraper.event_locations(detail)
  end

  def test_url_is_the_venue_official_website
    assert_equal "https://kofmehl.net/programm/malevolence/",
                 scraper_on(detail).event_url(DETAIL_URL)
  end

  def test_url_skips_a_link_to_the_venue_homepage
    homepage = page_from_html('<html><body><a href="https://kofmehl.net/de">Kofmehl</a></body></html>', DETAIL_URL)
    assert_equal DETAIL_URL, scraper_on(homepage).event_url(DETAIL_URL)
  end

  def test_homepage_is_the_bare_domain_or_a_language_root
    assert Scrapers::Petzi.homepage?("https://www.fri-son.ch")
    assert Scrapers::Petzi.homepage?("https://sedel.ch/")
    assert Scrapers::Petzi.homepage?("https://www.fri-son.ch/fr")
    refute Scrapers::Petzi.homepage?("https://kofmehl.net/programm/malevolence/")
    refute Scrapers::Petzi.homepage?("https://www.fri-son.ch/fr/programme/2026/11/sniper-fr")
    refute Scrapers::Petzi.homepage?("https://www.sudpol.ch/?event=42")
  end

  def test_url_falls_back_to_petzi_when_no_venue_link
    bare = page_from_html('<html><body><a href="https://www.petzi.ch/x">x</a></body></html>', DETAIL_URL)
    assert_equal DETAIL_URL, scraper_on(bare).event_url(DETAIL_URL)
  end
end
