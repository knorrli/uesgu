require_relative "../../db_test_helper"
require_relative "../../support/counting_scraper_harness"

class Scrapers::CountingTest < ActiveSupport::TestCase
  test "tallies created + collects ids, then unchanged on an identical re-scrape" do
    rows = [{ url: "https://fixture.test/e1" }, { url: "https://fixture.test/e2" }]
    CountingScraperHarness.next_rows = rows

    result = CountingScraperHarness.new.call

    assert_equal 2, result.seen
    assert_equal 2, result.created
    assert_equal 0, result.updated
    assert_equal 0, result.unchanged
    assert_equal 0, result.errored
    created = Event.where(url: rows.map { |r| r[:url] })
    assert_equal created.pluck(:id).sort, result.created_ids.sort

    again = CountingScraperHarness.new.call
    assert_equal 0, again.created
    assert_equal 0, again.updated
    assert_equal 2, again.unchanged
    assert_empty again.created_ids
  end

  test "a re-scrape with changed data counts as updated" do
    url = "https://fixture.test/changer"
    CountingScraperHarness.next_rows = [{ url: url, title: "First Title" }]
    CountingScraperHarness.new.call

    CountingScraperHarness.next_rows = [{ url: url, title: "Second Title" }]
    result = CountingScraperHarness.new.call

    assert_equal 0, result.created
    assert_equal 1, result.updated
    assert_equal 0, result.unchanged
    assert_equal "Second Title", Event.find_by(url: url).title
  end

  test "a single bad event is errored without aborting the rest" do
    CountingScraperHarness.next_rows = [
      { url: "https://fixture.test/good1" },
      { url: "https://fixture.test/bad", bad: true },
      { url: "https://fixture.test/good2" }
    ]

    result = CountingScraperHarness.new.call

    assert_equal 3, result.seen
    assert_equal 2, result.created
    assert_equal 1, result.errored
    assert_equal 2, result.created_ids.size
    assert_not Event.exists?(url: "https://fixture.test/bad")
  end

  test "a locked field survives a re-scrape while other fields still update" do
    url = "https://fixture.test/locked"
    CountingScraperHarness.next_rows = [{ url: url, title: "Real Title", description: "First Sub" }]
    CountingScraperHarness.new.call
    event = Event.find_by(url: url)
    event.lock_field!(:title)

    CountingScraperHarness.next_rows = [{ url: url, title: "Source Title", description: "Second Sub" }]
    result = CountingScraperHarness.new.call

    assert_equal 1, result.updated
    assert_equal 0, result.unchanged
    event.reload
    assert_equal "Real Title", event.title
    assert_equal "Second Sub", event.description
  end

  test "a re-scrape that only touches a locked field counts as unchanged" do
    url = "https://fixture.test/locked-only"
    CountingScraperHarness.next_rows = [{ url: url, title: "Kept Title" }]
    CountingScraperHarness.new.call
    Event.find_by(url: url).lock_field!(:title)

    CountingScraperHarness.next_rows = [{ url: url, title: "Ignored New Title" }]
    result = CountingScraperHarness.new.call

    assert_equal 0, result.updated
    assert_equal 1, result.unchanged
    assert_equal "Kept Title", Event.find_by(url: url).title
  end

  test "a dismissed event is not resurrected or updated by a re-scrape" do
    url = "https://fixture.test/dismissed"
    CountingScraperHarness.next_rows = [{ url: url, title: "Original" }]
    CountingScraperHarness.new.call
    dismissed = Event.find_by(url: url)
    dismissed.dismiss!

    CountingScraperHarness.next_rows = [{ url: url, title: "Changed" }]
    result = CountingScraperHarness.new.call

    assert_equal 0, result.created
    assert_equal 0, result.updated
    assert_equal 0, result.unchanged
    assert dismissed.reload.dismissed?
    assert_equal "Original", dismissed.title
  end

  test "an undismissed event is updated again by the next re-scrape" do
    url = "https://fixture.test/undismissed"
    CountingScraperHarness.next_rows = [{ url: url, title: "Original" }]
    CountingScraperHarness.new.call
    event = Event.find_by(url: url)
    event.dismiss!
    event.undismiss!

    CountingScraperHarness.next_rows = [{ url: url, title: "Changed" }]
    result = CountingScraperHarness.new.call

    assert_equal 1, result.updated
    assert_equal "Changed", event.reload.title
  end

  test "a scraped event matching an active discard rule is flagged, and cleared when the rule goes" do
    url = "https://fixture.test/discard"
    DiscardRule.create!(pattern: "Tschütte")
    CountingScraperHarness.next_rows = [{ url: url, title: "Tschütte live" }]
    result = CountingScraperHarness.new.call
    event = Event.find_by(url: url)
    assert event.discarded?, "event should be flagged by the matching rule"
    assert_equal 1, result.discarded, "the run should tally the filtered event"

    DiscardRule.destroy_all
    CountingScraperHarness.next_rows = [{ url: url, title: "Tschütte live" }]
    CountingScraperHarness.new.call
    refute event.reload.discarded?
  end

  test "an identical re-scrape with a duplicate-carrying genre list stays unchanged" do
    url = "https://fixture.test/genre-overlap"
    rows = [{ url: url, genres: %w[Ggg Ggg] }]
    CountingScraperHarness.next_rows = rows
    CountingScraperHarness.new.call
    assert_equal ["Ggg"], Event.find_by(url: url).genre_list

    CountingScraperHarness.next_rows = rows
    again = CountingScraperHarness.new.call
    assert_equal 0, again.updated, "a no-op re-scrape must not count as updated"
    assert_equal 1, again.unchanged
  end

  test "a reschedule marker in the title sets rescheduled_at, and clears when the marker goes" do
    url = "https://fixture.test/moved"
    CountingScraperHarness.next_rows = [{ url: url, title: "Verschoben: The Band" }]
    CountingScraperHarness.new.call
    event = Event.find_by(url: url)
    assert event.rescheduled?, 'a "Verschoben" title should flag the event as rescheduled'
    first_at = event.rescheduled_at

    CountingScraperHarness.next_rows = [{ url: url, title: "Verschoben: The Band" }]
    CountingScraperHarness.new.call
    assert_equal first_at, event.reload.rescheduled_at

    CountingScraperHarness.next_rows = [{ url: url, title: "The Band" }]
    CountingScraperHarness.new.call
    refute event.reload.rescheduled?
  end

  test "a re-scrape leaves an admin-pinned genre list alone" do
    url = "https://fixture.test/pinned-genres"
    CountingScraperHarness.next_rows = [{ url: url, title: "Show", genres: ["Aaa"] }]
    CountingScraperHarness.new.call
    event = Event.find_by(url: url)
    event.genre_list = ["Bbb"]
    event.lock_field!(:genres)
    event.save!

    CountingScraperHarness.next_rows = [{ url: url, title: "Show", genres: ["Aaa"] }]
    CountingScraperHarness.new.call

    assert_equal ["Bbb"], event.reload.genre_list
  end
end
