require_relative '../db_test_helper'

class ScrapeRunTest < ActiveSupport::TestCase
  test 'prune! keeps only the most recent runs' do
    runs = Array.new(4) { |i| ScrapeRun.create!(started_at: Time.zone.local(2030, 1, 1, 0, i)) }
    ScrapeRun.prune!(keep: 2)
    assert_equal runs.last(2).map(&:id).sort, ScrapeRun.pluck(:id).sort
  end

  test 'destroying a run cascades its results away' do
    run = ScrapeRun.create!(started_at: Time.zone.local(2030, 1, 1))
    run.scrape_results.create!(scraper: 'x', status: :ok)

    assert_difference -> { ScrapeResult.count }, -1 do
      run.destroy
    end
  end

  test 'pruning a run nullifies its created events but keeps them' do
    run = ScrapeRun.create!(started_at: Time.zone.local(2030, 1, 1))
    created = event(created_in_scrape_run: run)

    run.destroy

    assert Event.exists?(created.id)
    assert_nil created.reload.created_in_scrape_run_id
  end

  test 'needs_attention? when any scraper failed or came back empty' do
    assert ScrapeRun.new(scrapers_failed: 1).needs_attention?
    assert ScrapeRun.new(scrapers_empty: 2).needs_attention?
    assert_not ScrapeRun.new(scrapers_ok: 5).needs_attention?
  end

  test 'duration is nil until finished, then the elapsed seconds' do
    run = ScrapeRun.new(started_at: Time.zone.local(2030, 1, 1, 0, 0))
    assert_nil run.duration
    run.finished_at = Time.zone.local(2030, 1, 1, 0, 1)
    assert_in_delta 60, run.duration, 0.001
  end
end
