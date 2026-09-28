require_relative "../../db_test_helper"
require_relative "../../support/counting_scraper_harness"

class Scrapers::EventPageScheduleTest < ActiveSupport::TestCase
  class PageOpeningHarness < CountingScraperHarness
    self.opens_event_pages = true
  end
  Scrapers::All.scrapers.delete("PageOpeningHarness")

  Checked = Struct.new(:start_date, :event_page_checked_at, keyword_init: true)

  TODAY = Date.new(2030, 1, 1)

  def due?(days_away:, checked_days_ago:)
    event = Checked.new(start_date: TODAY + days_away,
                        event_page_checked_at: checked_days_ago && (TODAY - checked_days_ago).to_time)
    Scrapers::EventPageSchedule.due?(event, today: TODAY)
  end

  test "a page never opened is due" do
    assert due?(days_away: 60, checked_days_ago: nil)
  end

  test "more than a week out, a page is reopened weekly" do
    assert_not due?(days_away: 20, checked_days_ago: 6)
    assert due?(days_away: 20, checked_days_ago: 7)
  end

  test "within the week, a page is reopened every two days" do
    assert_not due?(days_away: 5, checked_days_ago: 1)
    assert due?(days_away: 5, checked_days_ago: 2)
  end

  test "within three days, a page is reopened nightly" do
    assert_not due?(days_away: 2, checked_days_ago: 0)
    assert due?(days_away: 2, checked_days_ago: 1)
  end

  test "an event whose page is not due is counted unchanged and left as it was" do
    url = "https://fixture.test/paged"
    PageOpeningHarness.next_rows = [{ url: url, title: "First Title" }]
    PageOpeningHarness.new.call
    assert Event.find_by(url: url).event_page_checked_at

    PageOpeningHarness.next_rows = [{ url: url, title: "Second Title" }]
    result = PageOpeningHarness.new.call

    assert_equal 1, result.seen
    assert_equal 1, result.unchanged
    assert_equal "First Title", Event.find_by(url: url).title
  end

  test "an event whose page is due again is rebuilt" do
    url = "https://fixture.test/paged-later"
    PageOpeningHarness.next_rows = [{ url: url, title: "First Title" }]
    PageOpeningHarness.new.call

    PageOpeningHarness.next_rows = [{ url: url, title: "Second Title" }]
    result = travel(7.days) { PageOpeningHarness.new.call }

    assert_equal 1, result.updated
    assert_equal "Second Title", Event.find_by(url: url).title
  end

  test "PETZI recognises a known event by its petzi.ch page without opening it" do
    row = "https://www.petzi.ch/en/events/61806-kulturfabrik-kofmehl-malevolence/"
    event(url: "https://fixture.test/kofmehl-malevolence", aggregator_url: row,
          event_page_checked_at: Time.current)
    petzi = Scrapers::Petzi.new
    opened = []
    petzi.define_singleton_method(:get) { |uri, *| opened << uri.to_s and nil }
    petzi.define_singleton_method(:event_rows) { [row] }

    result = petzi.call

    assert_equal [Scrapers::Petzi.url.to_s], opened
    assert_equal 1, result.unchanged
  end

  test "a scraper that reads only the programme rebuilds every event every run" do
    url = "https://fixture.test/programme-only"
    CountingScraperHarness.next_rows = [{ url: url, title: "First Title" }]
    CountingScraperHarness.new.call

    CountingScraperHarness.next_rows = [{ url: url, title: "Second Title" }]
    CountingScraperHarness.new.call

    event = Event.find_by(url: url)
    assert_equal "Second Title", event.title
    assert_nil event.event_page_checked_at
  end
end
