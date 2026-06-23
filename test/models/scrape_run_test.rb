require_relative "../db_test_helper"

class ScrapeRunTest < ActiveSupport::TestCase
  test "prune! keeps only the most recent runs" do
    runs = Array.new(4) { |i| ScrapeRun.create!(started_at: Time.zone.local(2030, 1, 1, 0, i)) }
    ScrapeRun.prune!(keep: 2)
    assert_equal runs.last(2).map(&:id).sort, ScrapeRun.pluck(:id).sort
  end

  test "destroying a run cascades its results away" do
    run = ScrapeRun.create!(started_at: Time.zone.local(2030, 1, 1))
    run.scrape_results.create!(scraper: "x", status: :ok)

    assert_difference -> { ScrapeResult.count }, -1 do
      run.destroy
    end
  end

  test "pruning a run nullifies its created events but keeps them" do
    run = ScrapeRun.create!(started_at: Time.zone.local(2030, 1, 1))
    created = event(created_in_scrape_run: run)

    run.destroy

    assert Event.exists?(created.id)
    assert_nil created.reload.created_in_scrape_run_id
  end

  test "needs_attention? when any scraper failed or came back empty" do
    assert ScrapeRun.new(scrapers_failed: 1).needs_attention?
    assert ScrapeRun.new(scrapers_empty: 2).needs_attention?
    assert_not ScrapeRun.new(scrapers_ok: 5).needs_attention?
  end

  test "duration is nil until finished, then the elapsed seconds" do
    run = ScrapeRun.new(started_at: Time.zone.local(2030, 1, 1, 0, 0))
    assert_nil run.duration
    run.finished_at = Time.zone.local(2030, 1, 1, 0, 1)
    assert_in_delta 60, run.duration, 0.001
  end

  test "previous is the most recent finished run before this one" do
    old = finished_run(Time.zone.local(2030, 1, 1))
    recent = finished_run(Time.zone.local(2030, 1, 2))
    current = finished_run(Time.zone.local(2030, 1, 3))

    assert_equal recent.id, current.previous.id
    assert_equal old.id, recent.previous.id
    assert_nil old.previous
  end

  test "dropped_to_zero flags only venues that were ok last run and empty now" do
    prev = finished_run(Time.zone.local(2030, 1, 1))
    prev.scrape_results.create!(scraper: "steady",  status: :ok)
    prev.scrape_results.create!(scraper: "broke",   status: :ok)
    prev.scrape_results.create!(scraper: "chronic", status: :empty)

    run = finished_run(Time.zone.local(2030, 1, 2))
    run.scrape_results.create!(scraper: "steady",  status: :ok)    # still fine
    run.scrape_results.create!(scraper: "broke",   status: :empty) # silent drop
    run.scrape_results.create!(scraper: "chronic", status: :empty) # empty both runs
    run.scrape_results.create!(scraper: "fresh",   status: :empty) # no baseline

    assert_equal %w[broke], run.dropped_to_zero
  end

  test "dropped_to_zero is empty when there is no previous run" do
    run = finished_run(Time.zone.local(2030, 1, 1))
    run.scrape_results.create!(scraper: "broke", status: :empty)

    assert_empty run.dropped_to_zero
  end

  private

  def finished_run(started_at)
    ScrapeRun.create!(started_at:, finished_at: started_at + 1.minute, status: :finished)
  end
end
