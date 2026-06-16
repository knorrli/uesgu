require_relative '../../db_test_helper'
require_relative '../../support/counting_scraper_harness'
require 'stringio'

# Scrapers::Sweep is the orchestration behind scrapers:run_all: one ScrapeRun,
# a ScrapeResult per scraper, the created events stamped with the run.
class Scrapers::SweepTest < ActiveSupport::TestCase
  def sweep(scrapers)
    Scrapers::Sweep.run!(scrapers: scrapers, out: StringIO.new)
  end

  test 'records an ok run and links the events it created' do
    CountingScraperHarness.next_rows = [
      { url: 'https://fixture.test/a' }, { url: 'https://fixture.test/b' }
    ]

    run = sweep('CountingScraperHarness' => CountingScraperHarness)

    assert run.finished?
    assert run.finished_at
    assert_equal 1, run.scrapers_total
    assert_equal 1, run.scrapers_ok
    assert_equal 0, run.scrapers_empty
    assert_equal 0, run.scrapers_failed

    result = run.scrape_results.sole
    assert_equal 'ok', result.status
    assert_equal 2, result.created_count
    assert_equal 'counting_scraper_harness', result.scraper

    assert_equal 2, run.created_events.count
    assert(run.created_events.all? { |e| e.created_in_scrape_run_id == run.id })
  end

  test 'records how many events a run filtered via discard rules' do
    DiscardRule.create!(pattern: 'zorp')
    CountingScraperHarness.next_rows = [
      { url: 'https://fixture.test/a', title: 'zorp fest' },
      { url: 'https://fixture.test/b', title: 'real concert' }
    ]

    run = sweep('CountingScraperHarness' => CountingScraperHarness)

    assert_equal 1, run.scrape_results.sole.discarded_count
  end

  test 'a scraper that writes nothing is recorded empty (the silent regression)' do
    CountingScraperHarness.next_rows = []

    run = sweep('CountingScraperHarness' => CountingScraperHarness)

    assert_equal 1, run.scrapers_empty
    assert run.needs_attention?
    assert_equal 'empty', run.scrape_results.sole.status
  end

  test 'a raising scraper is recorded failed, not fatal to the sweep' do
    failing = Class.new do
      def self.url = 'https://fixture.test/down'
      def self.call = raise(StandardError, 'site down')
    end

    run = sweep('Failing' => failing)

    assert_equal 1, run.scrapers_failed
    assert run.finished?
    result = run.scrape_results.sole
    assert_equal 'failed', result.status
    assert_equal 'StandardError', result.error_class
    assert_equal 'site down', result.error_message
  end
end
