require "test_helper"

class Scrapers::XTraTest < Minitest::Test
  def test_combined_music_styles_split_on_slash_and_comma
    assert_equal %w[Zorp Blorp], genres_for("Zorp / Blorp")
    assert_equal %w[Zorp Blorp], genres_for("Zorp/ Blorp")
    assert_equal %w[Zorp Blorp], genres_for("Zorp, Blorp")
    assert_equal ["Zorp Music"], genres_for("Zorp Music")
  end

  def test_an_event_without_a_music_style_has_no_genres
    assert_equal [], Scrapers::XTra.new.event_genres(detail)
  end

  def test_the_main_hall_and_the_musikcafe_are_kept_and_a_foreign_venue_is_skipped
    refute skipped?(detail), "the main hall names no location"
    refute skipped?(detail(info: { "Location" => "X-TRA Musikcafe" }))
    assert skipped?(detail(info: { "Location" => "Altes Grbhaus" }))
  end

  def test_an_unreachable_detail_page_is_left_to_the_per_event_failure_count
    scraper = Scrapers::XTra.new
    scraper.define_singleton_method(:detail_page) { |_row| raise Mechanize::ResponseCodeError.new(Struct.new(:code).new("404")) }
    refute scraper.skip_row?(Nokogiri::HTML.fragment("<li></li>"))
  end

  def test_start_time_is_the_structured_start_not_the_doors
    content = detail(start: "2026-10-08T19:45", info: { "Türöffnung" => "19:00 Uhr" })
    assert_equal Time.zone.local(2026, 10, 8, 19, 45), Scrapers::XTra.new.event_start_time(content)
  end

  def test_an_event_without_a_start_raises_rather_than_dating_it_today
    error = assert_raises(RuntimeError) { Scrapers::XTra.new.event_start_time(detail(start: nil)) }
    assert_match "Zorp Night", error.message
  end

  def test_a_failed_load_more_keeps_the_first_page
    scraper = scraper_on(list_page)
    scraper.define_singleton_method(:post) { |*| raise Mechanize::ResponseCodeError.new(Struct.new(:code).new("500")) }
    assert_equal ["/de/programm/konzerte/1/zorp-night.html"], row_hrefs(scraper)
  end

  def test_load_more_posts_the_pages_csrf_token_and_appends_its_events
    scraper = scraper_on(list_page)
    posted = headers = nil
    more = { events: %(<ul class="tile"><li><a href="/de/programm/konzerte/2/blorp.html"></a></li></ul>) }.to_json
    scraper.define_singleton_method(:post) do |_url, params, sent_headers|
      posted = params
      headers = sent_headers
      Mechanize::File.new(URI("https://www.x-tra.ch/"), {}, more, "200")
    end

    assert_equal ["/de/programm/konzerte/1/zorp-night.html", "/de/programm/konzerte/2/blorp.html"], row_hrefs(scraper)
    assert_equal({ action: "column_events_load_more", csrf_token: "tok" }, posted)
    assert_equal "XMLHttpRequest", headers["X-Requested-With"], "without it the server answers with the whole HTML page"
  end

  private

  def genres_for(style)
    Scrapers::XTra.new.event_genres(detail(info: { "Musikstil" => style }))
  end

  def skipped?(content)
    scraper = Scrapers::XTra.new
    scraper.define_singleton_method(:detail_page) { |_row| content }
    scraper.skip_row?(Nokogiri::HTML.fragment("<li></li>"))
  end

  def detail(start: "2026-10-08T20:00", info: {})
    structured = { "@type" => "MusicEvent", "name" => "Zorp Night", "startDate" => start }.compact
    Nokogiri::HTML(<<~HTML)
      <div class="featured"><div class="caption"><h2>Zorp Night</h2></div></div>
      <div class="event"><ul class="info">
        #{info.map { |label, value| "<li><span>#{label}</span><strong>#{value}</strong></li>" }.join}
      </ul></div>
      <script type="application/ld+json">#{structured.to_json}</script>
    HTML
  end

  def list_page
    html = <<~HTML
      <meta name="csrf-token" content="tok">
      <div class="featured"><ul class="rslides"><li><a href="/de/programm/konzerte/1/zorp-night.html"></a></li></ul></div>
      <div class="events"><ul class="tile"><li><a href="/de/programm/konzerte/1/zorp-night.html"></a></li></ul></div>
    HTML
    Mechanize::Page.new(Scrapers::XTra.url, { "content-type" => "text/html" }, html, "200", Mechanize.new)
  end

  def scraper_on(page)
    Scrapers::XTra.new.tap { |scraper| scraper.define_singleton_method(:page) { page } }
  end

  def row_hrefs(scraper)
    scraper.event_rows.map { |row| row.at_css("a")["href"] }
  end
end
