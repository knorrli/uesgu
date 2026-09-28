require "test_helper"

class Scrapers::DescriptionMiningTest < Minitest::Test
  FIXTURE_ROOT = File.expand_path("../../fixtures/scrapers", __dir__)

  def fixture(slug, name)
    File.read(File.join(FIXTURE_ROOT, slug, name))
  end

  def html(slug, name = "list.html")
    Nokogiri::HTML(fixture(slug, name))
  end

  def test_kairo_mines_the_text_prose_after_the_title
    row = html("kairo").at_css('article[id^="kultur_"]')
    text = Scrapers::Kairo.new.event_genre_prose(row)

    assert_includes text, "Musikförderung"      #
    refute_includes text, "Meet the Pros"
  end

  def test_helsinki_mines_the_description_block
    row = html("helsinki").at_css("div.event")
    text = Scrapers::Helsinki.new.event_genre_prose(row)

    assert_includes text, "Film"
  end

  def test_boeroem_mines_the_post_content_not_the_newsletter_box
    text = Scrapers::Boeroem.new.event_genre_prose(html("boeroem", "detail.html"))

    assert_includes text, "Grill"
    refute_includes text, "Newsletter"
  end

  def test_docks_mines_the_artist_texts
    text = Scrapers::Docks.new.event_genre_prose(html("docks", "detail.html"))

    assert_includes text, "groupe de rock"
  end

  def test_dynamo_mines_the_html_description_as_plain_text
    row = Array(JSON.parse(fixture("dynamo", "list.html"))["data"])
          .find { |r| r.dig("attributes", "field_event_description", "value").present? }
    text = Scrapers::Dynamo.new.event_genre_prose(row)

    assert_includes text, "Hardcore-Punk"
    refute_includes text, "<p"
  end

  def test_kofmehl_mines_the_wysiwyg_text
    text = Scrapers::Kofmehl.new.event_genre_prose(html("kofmehl", "detail.html"))

    assert_includes text, "Schlagzeug"
  end

  def test_neubad_mines_the_text_tab_not_the_easy_language_tab
    text = Scrapers::Neubad.new.event_genre_prose(html("neubad", "detail.html"))

    assert_includes text, "Geschäftsübergabe"
    refute_includes text, "Die alte Neubad Geschäftsführung"
  end

  def test_nouveau_monde_mines_the_text_area
    text = Scrapers::NouveauMonde.new.event_genre_prose(html("nouveau_monde", "detail.html"))

    assert_includes text, "For fans of"
  end

  def test_nouveau_monde_reads_the_genre_list_of_every_act_once
    page = Nokogiri::HTML(<<~HTML)
      <section class="groupHeading"><ul class="flexRow"><li>Rap</li><li>Trap</li></ul></section>
      <section class="groupHeading"><ul class="flexRow"><li>Rap</li><li> </li></ul></section>
    HTML

    assert_equal %w[Rap Trap], Scrapers::NouveauMonde.new.event_genres(page)
  end

  def test_sous_soul_mines_the_rich_text_not_the_site_chrome
    text = Scrapers::SousSoul.new.event_genre_prose(html("sous_soul", "detail.html"))

    assert_includes text, "Ausstellungsdokumentation"
    refute_includes text, "Ehemaligen Theater"
  end

  def test_zent_mines_the_row_text
    row = html("zent").at_css("article.event-item")
    text = Scrapers::Zent.new.event_genre_prose(row)

    assert_includes text, "Vegan"
  end

  def test_volkshaus_mines_the_collapse_panel_prose
    row = html("volkshaus").at_css("#programmliste .tableitem.event")
    text = Scrapers::Volkshaus.new.event_genre_prose(row)

    assert_includes text, "Jazzgeschichte"
  end

  def test_rote_fabrik_mines_and_strips_the_html_description
    row = JSON.parse(fixture("rote_fabrik", "list.html")).values.first
    text = Scrapers::RoteFabrik.new.event_genre_prose(row)

    assert_includes text, "experimental music"
    refute_includes text, "<p"
  end

  def test_bierhuebeli_mines_the_musicradar_stil_line_only
    row  = JSON.parse(fixture("bierhuebeli", "list.html"))
             .find { |r| r["link"].to_s.include?("best-of-2000er-party-september") }
    text = Scrapers::Bierhuebeli.new.event_genre_prose(row)

    assert_includes text, "Heartbeat-Faktor"
    refute_includes text, "kollektiver"
  end

  def test_kaserne_mines_its_event_page_not_the_credits_or_related_events
    text = prose_from_event_page(Scrapers::Kaserne, "kaserne", ".index details.concert-type")

    assert_includes text, "Long String Instrument"
    refute_includes text, "ist eine Community"
    refute_includes text, "Soundkunst im Salonformat"
  end

  def test_dampfzentrale_mines_its_event_page_not_the_ticket_info_or_credits
    text = prose_from_event_page(Scrapers::Dampfzentrale, "dampfzentrale", ".event-entry")

    assert_includes text, "Masterclass"
    refute_includes text, "Bequeme Kleidung"
    refute_includes text, "Grafik:"
  end

  def test_saegegasse_mines_its_event_page_not_the_footer
    text = prose_from_event_page(Scrapers::Saegegasse, "saegegasse", ".rs_events_container .rs_event_detail")

    assert_includes text, "Indie-Pop-Band"
    refute_includes text, "Impressum"
  end

  def test_treibhaus_mines_its_event_page_not_the_house_rules
    text = prose_from_event_page(Scrapers::Treibhaus, "treibhaus", ".programm-list li.mb-10")

    assert_includes text, "Brazen Barbie"
    refute_includes text, "Rollstuhlfahrer"
  end

  def test_mahogany_hall_mines_its_event_page_not_the_sidebar
    text = prose_from_event_page(Scrapers::MahoganyHall, "mahogany_hall", ".view-konzerte .views-row")

    assert_includes text, "Electric Blues"
    refute_includes text, "Passiv-Mitglied"
  end

  private

  def prose_from_event_page(scraper_class, slug, row_selector)
    row = html(slug).at_css(row_selector)
    scraper = scraper_class.new
    event_page = html(slug, "detail.html")
    fetched = []
    scraper.define_singleton_method(:get) { |url| fetched << url; event_page }

    text = scraper.event_genre_prose(row)
    assert_equal [scraper.event_url(row)], fetched
    text
  end
end
