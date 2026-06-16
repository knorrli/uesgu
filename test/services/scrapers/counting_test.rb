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

  test 'a locked field survives a re-scrape while other fields still update' do
    url = 'https://fixture.test/locked'
    CountingScraperHarness.next_rows = [{ url: url, title: 'Real Title', subtitle: 'First Sub' }]
    CountingScraperHarness.new.call
    event = Event.find_by(url: url)
    event.lock_field!(:title) # admin corrected the title

    # Source changes both fields; the locked title must be preserved, the
    # unlocked subtitle must track the source → a real change → updated.
    CountingScraperHarness.next_rows = [{ url: url, title: 'Source Title', subtitle: 'Second Sub' }]
    result = CountingScraperHarness.new.call

    assert_equal 1, result.updated
    assert_equal 0, result.unchanged
    event.reload
    assert_equal 'Real Title', event.title
    assert_equal 'Second Sub', event.subtitle
  end

  test 'a re-scrape that only touches a locked field counts as unchanged' do
    url = 'https://fixture.test/locked-only'
    CountingScraperHarness.next_rows = [{ url: url, title: 'Kept Title' }]
    CountingScraperHarness.new.call
    Event.find_by(url: url).lock_field!(:title)

    # The only source change is the locked title → the event is effectively
    # untouched, so it tallies as unchanged, not updated.
    CountingScraperHarness.next_rows = [{ url: url, title: 'Ignored New Title' }]
    result = CountingScraperHarness.new.call

    assert_equal 0, result.updated
    assert_equal 1, result.unchanged
    assert_equal 'Kept Title', Event.find_by(url: url).title
  end

  test 'a dismissed event is not resurrected or updated by a re-scrape' do
    url = 'https://fixture.test/dismissed'
    CountingScraperHarness.next_rows = [{ url: url, title: 'Original' }]
    CountingScraperHarness.new.call
    dismissed = Event.find_by(url: url)
    dismissed.dismiss!

    # Same url still in the source with changed data — the scraper must leave the
    # dismissed event untouched rather than update it back into view.
    CountingScraperHarness.next_rows = [{ url: url, title: 'Changed' }]
    result = CountingScraperHarness.new.call

    assert_equal 0, result.created
    assert_equal 0, result.updated
    assert_equal 0, result.unchanged
    assert dismissed.reload.dismissed?
    assert_equal 'Original', dismissed.title
  end

  test 'an undismissed event is updated again by the next re-scrape' do
    url = 'https://fixture.test/undismissed'
    CountingScraperHarness.next_rows = [{ url: url, title: 'Original' }]
    CountingScraperHarness.new.call
    event = Event.find_by(url: url)
    event.dismiss!
    event.undismiss!

    # No longer dismissed → the scraper resumes updating it from source.
    CountingScraperHarness.next_rows = [{ url: url, title: 'Changed' }]
    result = CountingScraperHarness.new.call

    assert_equal 1, result.updated
    assert_equal 'Changed', event.reload.title
  end

  test 'a scraped event matching an active discard rule is flagged, and cleared when the rule goes' do
    url = 'https://fixture.test/discard'
    DiscardRule.create!(pattern: 'Tschütte')
    CountingScraperHarness.next_rows = [{ url: url, title: 'Tschütte live' }]
    CountingScraperHarness.new.call
    event = Event.find_by(url: url)
    assert event.discarded?, 'event should be flagged by the matching rule'

    # Rule gone → next scrape re-derives the flag to nil (not sticky).
    DiscardRule.destroy_all
    CountingScraperHarness.next_rows = [{ url: url, title: 'Tschütte live' }]
    CountingScraperHarness.new.call
    refute event.reload.discarded?
  end

  test 'a re-scrape leaves an admin-pinned genre list alone but re-derives styles' do
    url = 'https://fixture.test/pinned-genres'
    CountingScraperHarness.next_rows = [{ url: url, title: 'Show', genres: ['Aaa'] }]
    CountingScraperHarness.new.call
    event = Event.find_by(url: url)
    event.genre_list = ['Bbb']
    event.lock_field!(:genres)
    event.save!

    # Source still says "Aaa" — but genres are pinned, so the re-scrape keeps
    # "Bbb" rather than overwriting it.
    CountingScraperHarness.next_rows = [{ url: url, title: 'Show', genres: ['Aaa'] }]
    CountingScraperHarness.new.call

    assert_equal ['Bbb'], event.reload.genre_list
  end
end
