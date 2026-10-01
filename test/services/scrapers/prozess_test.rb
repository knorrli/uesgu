require "test_helper"

class Scrapers::ProzessTest < Minitest::Test
  TODAY = Date.new(2026, 10, 1)

  def test_a_single_date_is_one_event_at_its_time
    assert_equal [["https://prozess.be/programm/1", "2026-10-04 20:00"]], showings("date" => "04.10.2026", "time" => "20:00")
  end

  def test_an_untimed_range_is_a_residency_and_yields_nothing
    assert_empty showings("firstdate" => "04.10.2026", "lastdate" => "31.10.2026")
  end

  def test_a_timed_range_is_one_event_per_day
    assert_equal [["https://prozess.be/programm/1#2026-10-20", "2026-10-20 21:00"],
                  ["https://prozess.be/programm/1#2026-10-21", "2026-10-21 21:00"]],
                 showings("firstdate" => "20.10.2026", "lastdate" => "21.10.2026", "time" => "21:00")
  end

  def test_a_date_list_is_one_event_per_date_and_drops_the_past
    assert_equal [["https://prozess.be/programm/1#2026-10-22", "2026-10-22 20:00"],
                  ["https://prozess.be/programm/1#2026-11-26", "2026-11-26 20:00"]],
                 showings("dates" => "24.09.2026, 22.10.2026,26.11.2026", "time" => "20:00")
  end

  def test_paired_dates_take_their_own_times
    assert_equal [["https://prozess.be/programm/1#2026-10-24", "2026-10-24 20:30"],
                  ["https://prozess.be/programm/1#2026-10-25", "2026-10-25 10:00"]],
                 showings("firstdate" => "24.10.2026", "firsttime" => "20:30",
                          "seconddate" => "25.10.2026", "secondtime" => "Zorp ab 10:00")
  end

  def test_a_missing_time_falls_back_to_midnight
    assert_equal [["https://prozess.be/programm/1", "2026-10-29 00:00"]], showings("date" => "29.10.2026")
  end

  def test_a_hidden_entry_is_skipped
    assert_empty showings("date" => "04.10.2026", "hidden" => true)
  end

  def test_an_unparseable_date_raises_rather_than_dating_the_event_today
    error = assert_raises(RuntimeError) { showings("date" => "Oktober") }
    assert_match "Oktober", error.message
  end

  def test_title_drops_markup_entities_and_word_joiners
    scraper, row = scraper_and_rows("date" => "04.10.2026", "title" => "Zorp&nbsp;⁠–⁠&nbsp;Blorp<br>&amp; Friends")
    assert_equal "Zorp – Blorp & Friends", scraper.event_title(row.first)
  end

  def test_description_is_the_first_paragraph
    scraper, row = scraper_and_rows("date" => "04.10.2026", "text" => "Zorp <b>plays</b> Blorp.<br>Still one.<br><br>Second.")
    assert_equal "Zorp plays Blorp. Still one.", scraper.event_description(row.first)
  end

  private

  def showings(entry)
    scraper, rows = scraper_and_rows(entry)
    rows.map { |row| [scraper.event_url(row), scraper.event_start_time(row).strftime("%Y-%m-%d %H:%M")] }
  end

  def scraper_and_rows(entry)
    body = { "programm" => [{ "id" => 1, "title" => "Zorp Night" }.merge(entry)] }.to_json
    page = Mechanize::File.new(Scrapers::Prozess.url, {}, body, "200")
    scraper = Scrapers::Prozess.new
    scraper.define_singleton_method(:page) { page }
    [scraper, Date.stub(:current, TODAY) { scraper.event_rows }]
  end
end
