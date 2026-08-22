require_relative "../../db_test_helper"
require_relative "../../support/counting_scraper_harness"
require "stringio"

# Scrapers::Sweep is the orchestration behind scrapers:run_all: one ScrapeRun,
# a ScrapeResult per scraper, the created events stamped with the run.
class Scrapers::SweepTest < ActiveSupport::TestCase
  def sweep(scrapers)
    Scrapers::Sweep.run!(scrapers: scrapers, out: StringIO.new)
  end

  test "records an ok run and links the events it created" do
    CountingScraperHarness.next_rows = [
      { url: "https://fixture.test/a" }, { url: "https://fixture.test/b" }
    ]

    run = sweep("CountingScraperHarness" => CountingScraperHarness)

    assert run.finished?
    assert run.finished_at
    assert_equal 1, run.scrapers_total
    assert_equal 1, run.scrapers_ok
    assert_equal 0, run.scrapers_empty
    assert_equal 0, run.scrapers_failed

    result = run.scrape_results.sole
    assert_equal "ok", result.status
    assert_equal 2, result.created_count
    assert_equal "counting_scraper_harness", result.scraper

    assert_equal 2, run.created_events.count
    assert(run.created_events.all? { |e| e.created_in_scrape_run_id == run.id })
  end

  # The nightly re-derivations ride on the sweep, and a capture lead only ever
  # appears if this one is still wired in.
  test "the sweep nominates the captured places that keep hosting shows" do
    zorpsaal = place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    2.times { event(location_list: [zorpsaal.name, zorpsaal.locality, zorpsaal.canton]) }
    CountingScraperHarness.next_rows = []

    sweep("CountingScraperHarness" => CountingScraperHarness)

    assert_equal "Zorpsaal", VenueLead.find_by(source: CapturedVenueLeads::SOURCE).venue
  end

  test "records how many events a run filtered via discard rules" do
    DiscardRule.create!(pattern: "zorp")
    CountingScraperHarness.next_rows = [
      { url: "https://fixture.test/a", title: "zorp fest" },
      { url: "https://fixture.test/b", title: "real concert" }
    ]

    run = sweep("CountingScraperHarness" => CountingScraperHarness)

    assert_equal 1, run.scrape_results.sole.discarded_count
  end

  class RobotsNoteHarness < CountingScraperHarness
    NOTE = "https://fixture.test/robots.txt unreachable — Mechanize::ResponseCodeError: 500".freeze
    def robots_note = NOTE
  end
  Scrapers::All.scrapers.delete("RobotsNoteHarness")

  test "an unreachable robots.txt is recorded on the result and in the summary" do
    RobotsNoteHarness.next_rows = [{ url: "https://fixture.test/a" }]
    out = StringIO.new

    run = Scrapers::Sweep.run!(scrapers: { "RobotsNoteHarness" => RobotsNoteHarness }, out: out)

    result = run.scrape_results.sole
    assert_equal "ok", result.status, "an unreachable robots.txt is a note, not a failure"
    assert_equal RobotsNoteHarness::NOTE, result.robots_note
    assert_includes out.string, "ROBOTS #{RobotsNoteHarness::NOTE}"
  end

  test "a healthy run records no robots note" do
    CountingScraperHarness.next_rows = [{ url: "https://fixture.test/a" }]

    run = sweep("CountingScraperHarness" => CountingScraperHarness)

    assert_nil run.scrape_results.sole.robots_note
  end

  test "a scraper that writes nothing is recorded empty (the silent regression)" do
    CountingScraperHarness.next_rows = []

    run = sweep("CountingScraperHarness" => CountingScraperHarness)

    assert_equal 1, run.scrapers_empty
    assert run.needs_attention?
    assert_equal "empty", run.scrape_results.sole.status
  end

  test "an actively-snoozed scraper is skipped and recorded snoozed, not run" do
    CountingScraperHarness.next_rows = [{ url: "https://fixture.test/should-not-be-seen" }]
    ScraperSnooze.snooze!("counting_scraper_harness")

    run = sweep("CountingScraperHarness" => CountingScraperHarness)

    result = run.scrape_results.sole
    assert_equal "snoozed", result.status
    # Skipped entirely: no site hit, no events, and — the point — not an alert.
    assert_equal 0, result.created_count
    assert_equal 0, run.scrapers_ok
    assert_equal 0, run.scrapers_empty
    assert_equal 0, run.scrapers_failed
    refute run.needs_attention?
    assert_equal 0, run.created_events.count
  end

  test "an expired snooze lets the scraper run again and is pruned" do
    CountingScraperHarness.next_rows = [{ url: "https://fixture.test/a" }]
    ScraperSnooze.create!(scraper: "counting_scraper_harness", snoozed_until: 1.day.ago)

    run = sweep("CountingScraperHarness" => CountingScraperHarness)

    assert_equal "ok", run.scrape_results.sole.status
    assert_equal 0, ScraperSnooze.count, "expired snooze should be pruned during the sweep"
  end

  test "a raising scraper is recorded failed, not fatal to the sweep" do
    failing = Class.new do
      def self.url = "https://fixture.test/down"
      def self.call = raise(StandardError, "site down")
    end

    run = sweep("Failing" => failing)

    assert_equal 1, run.scrapers_failed
    assert run.finished?
    result = run.scrape_results.sole
    assert_equal "failed", result.status
    assert_equal "StandardError", result.error_class
    assert_equal "site down", result.error_message
  end
end
