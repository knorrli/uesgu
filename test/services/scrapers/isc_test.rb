require "test_helper"

class Scrapers::IscTest < ActiveSupport::TestCase
  test "an upcoming date later this year keeps the scrape year" do
    assert_equal 2026, start_time_for("20.06.", on: Date.new(2026, 6, 15)).year
  end

  test "a January event scraped in December rolls into next year" do
    assert_equal 2027, start_time_for("05.01.", on: Date.new(2026, 12, 28)).year
  end

  test "a late-December event scraped in December stays this year" do
    assert_equal 2026, start_time_for("30.12.", on: Date.new(2026, 12, 28)).year
  end

  test "a date already past this year is read as next year" do
    assert_equal 2027, start_time_for("10.06.", on: Date.new(2026, 6, 15)).year
  end

  test "parses the day, month and time alongside the inferred year" do
    t = start_time_for("05.01.", on: Date.new(2026, 12, 28))
    assert_equal [2027, 1, 5, 20, 0], [t.year, t.month, t.day, t.hour, t.min]
  end

  test "reads the click-to-load YouTube players, which carry only a bare video id" do
    content = Nokogiri::HTML(<<~HTML)
      <div class="youtube video_player" data-embed="XiafbsKgfD0" data-type="youtube"></div>
      <div class="youtube video_player" data-embed="bcaXABuQIBc" data-type="youtube"></div>
      <p><a href="https://shitkid.bandcamp.com/">Bandcamp</a></p>
    HTML

    assert_equal [youtube("XiafbsKgfD0"), youtube("bcaXABuQIBc")], Scrapers::Isc.new.send(:event_media, content)
  end

  test "a player id also found as a regular embed is listed once" do
    content = Nokogiri::HTML(<<~HTML)
      <div class="youtube video_player" data-embed="XiafbsKgfD0" data-type="youtube"></div>
      <iframe src="https://www.youtube.com/embed/XiafbsKgfD0"></iframe>
    HTML

    assert_equal [youtube("XiafbsKgfD0")], Scrapers::Isc.new.send(:event_media, content)
  end

  private

  def youtube(id) = { "provider" => "youtube", "id" => id }

  def start_time_for(date, on:, time: "20:00 Uhr")
    content = Nokogiri::HTML(<<~HTML)
      <div class="event_detail_header"><span class="event_title_date">#{date}</span></div>
      <div class="event_detail"><span class="facts_listing">#{time}</span></div>
    HTML

    travel_to(on) { Scrapers::Isc.new.event_start_time(content) }
  end
end
