require_relative '../../db_test_helper'
require_relative '../../support/counting_scraper_harness'

# The instrumentation Scrapers::Agent#call adds: a Scrapers::Result tallying
# what the run saw and wrote, plus the ids of the events it created.
class Scrapers::CountingTest < ActiveSupport::TestCase
  test 'tallies created + collects ids, then unchanged on an identical re-scrape' do
    rows = [{ url: 'https://fixture.test/e1' }, { url: 'https://fixture.test/e2' }]
    CountingScraperHarness.next_rows = rows

    result = CountingScraperHarness.new.call

    assert_equal 2, result.seen
    assert_equal 2, result.created
    assert_equal 0, result.updated
    assert_equal 0, result.unchanged
    assert_equal 0, result.skipped
    created = Event.where(url: rows.map { |r| r[:url] })
    assert_equal created.pluck(:id).sort, result.created_ids.sort

    # Same urls, identical data: re-saved but nothing changed → unchanged, not updated.
    again = CountingScraperHarness.new.call
    assert_equal 0, again.created
    assert_equal 0, again.updated
    assert_equal 2, again.unchanged
    assert_empty again.created_ids
  end

  test 'a re-scrape with changed data counts as updated' do
    url = 'https://fixture.test/changer'
    CountingScraperHarness.next_rows = [{ url: url, title: 'First Title' }]
    CountingScraperHarness.new.call

    # Same url, different title → a real change.
    CountingScraperHarness.next_rows = [{ url: url, title: 'Second Title' }]
    result = CountingScraperHarness.new.call

    assert_equal 0, result.created
    assert_equal 1, result.updated
    assert_equal 0, result.unchanged
    assert_equal 'Second Title', Event.find_by(url: url).title
  end

  test 'a single bad event is skipped without aborting the rest' do
    CountingScraperHarness.next_rows = [
      { url: 'https://fixture.test/good1' },
      { url: 'https://fixture.test/bad', bad: true },
      { url: 'https://fixture.test/good2' }
    ]

    result = CountingScraperHarness.new.call

    assert_equal 3, result.seen
    assert_equal 2, result.created
    assert_equal 1, result.skipped
    assert_equal 2, result.created_ids.size
    assert_not Event.exists?(url: 'https://fixture.test/bad')
  end
end
