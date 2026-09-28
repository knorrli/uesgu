require "test_helper"

class Scrapers::EventPageMediaTest < Minitest::Test
  FIXTURE_ROOT = File.expand_path("../../fixtures/scrapers", __dir__)

  def test_kaserne_reads_the_embedded_video
    assert_equal [youtube("mI_3DVHXLhM")], media_from_event_page(Scrapers::Kaserne, "kaserne", ".index details.concert-type")
  end

  def test_schueuer_reads_the_video_block
    assert_equal [youtube("5yWGkZ9-mZE"), youtube("U6pYmYW6oRs")],
                 media_from_event_page(Scrapers::Schueuer, "schueuer", ".viz-event-list-box")
  end

  def test_treibhaus_reads_the_artist_links_not_the_footer_playlist
    assert_equal [spotify("artist/5oD2uBWPlOllcHlul6BbAb"), spotify("artist/7krRGwtf9BlypHPR8D9EZW")],
                 media_from_event_page(Scrapers::Treibhaus, "treibhaus", ".programm-list li.mb-10")
  end

  def test_mahogany_hall_reads_the_linked_video
    assert_equal [youtube("S0xbvXghgNs")],
                 media_from_event_page(Scrapers::MahoganyHall, "mahogany_hall", ".view-konzerte .views-row")
  end

  def test_saegegasse_event_page_without_media
    assert_empty media_from_event_page(Scrapers::Saegegasse, "saegegasse", ".rs_events_container .rs_event_detail")
  end

  def test_dampfzentrale_event_page_without_media
    assert_empty media_from_event_page(Scrapers::Dampfzentrale, "dampfzentrale", ".event-entry")
  end

  def test_a_failed_fetch_does_not_hand_the_previous_page_to_the_next_event
    rows = Nokogiri::HTML(File.read(File.join(FIXTURE_ROOT, "kaserne", "list.html"))).css(".index details.concert-type").first(2)
    scraper = Scrapers::Kaserne.new
    responses = [Nokogiri::HTML(File.read(File.join(FIXTURE_ROOT, "kaserne", "detail.html"))), :error, Nokogiri::HTML("")]
    scraper.define_singleton_method(:get) do |_url|
      response = responses.shift
      raise Mechanize::ResponseCodeError.new(Struct.new(:code).new("500")) if response == :error

      response
    end

    refute_empty scraper.send(:event_media, rows[0])
    assert_raises(Mechanize::ResponseCodeError) { scraper.send(:event_media, rows[1]) }
    assert_empty scraper.send(:event_media, rows[1])
  end

  private

  def media_from_event_page(scraper_class, slug, row_selector)
    row = Nokogiri::HTML(File.read(File.join(FIXTURE_ROOT, slug, "list.html"))).at_css(row_selector)
    event_page = Nokogiri::HTML(File.read(File.join(FIXTURE_ROOT, slug, "detail.html")))
    scraper = scraper_class.new
    fetched = []
    scraper.define_singleton_method(:get) { |url| fetched << url; event_page }

    scraper.event_genre_prose(row)
    media = scraper.send(:event_media, row)
    assert_equal [scraper.event_url(row)], fetched, "genre mining and media must share one event-page fetch"
    media
  end

  def youtube(id) = { "provider" => "youtube", "id" => id }

  def spotify(id) = { "provider" => "spotify", "id" => id }
end
