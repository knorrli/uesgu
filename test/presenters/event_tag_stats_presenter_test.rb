require 'db_test_helper'

# Locks the curation-dashboard projections in EventTagStatsPresenter: location tag
# lookups scoped to Event taggings, and the genre buckets (in-use, placed,
# unplaced, ignored). Synthetic names only.
class EventTagStatsPresenterTest < ActiveSupport::TestCase
  setup { @presenter = EventTagStatsPresenter.new }

  test 'location_tags returns only location-context tags on events' do
    event = event_with_genres('some-genre')
    event.update!(location_list: ['Invented Venue'])

    names = @presenter.location_tags.map(&:name)

    assert_includes names, 'Invented Venue'
    refute_includes names, 'some-genre', 'genre tags must not leak into locations'
  end

  test 'genre_tags includes in-use genres and excludes dormant ones' do
    used = genre(name: 'used', events_count: 4)
    genre(name: 'dormant', events_count: 0)

    names = @presenter.genre_tags.pluck(:name)

    assert_includes names, used.name
    refute_includes names, 'dormant'
  end

  test 'placed_genre_tags lists only in-use genres filed under a parent' do
    root = genre(name: 'root', events_count: 2)
    placed = genre(name: 'placed', events_count: 2, parent: root)
    genre(name: 'bare', events_count: 2)

    names = @presenter.placed_genre_tags.pluck(:name)

    assert_includes names, placed.name
    refute_includes names, 'bare'
    refute_includes names, 'root' # in use but not placed (no parent)
  end

  test 'unplaced_genre_tags lists the in-use, undisposed, unfiled queue' do
    queued = genre(name: 'queued', events_count: 7)
    root = genre(name: 'root2', events_count: 7)
    genre(name: 'placed2', events_count: 7, parent: root)

    names = @presenter.unplaced_genre_tags.pluck(:name)

    assert_includes names, queued.name
    refute_includes names, 'placed2'
  end

  test 'ignored_genre_tags lists only in-use ignored genres' do
    ignored = genre(name: 'ignored', events_count: 3)
    ignored.ignore!
    genre(name: 'plain', events_count: 3)

    names = @presenter.ignored_genre_tags.pluck(:name)

    assert_includes names, ignored.name
    refute_includes names, 'plain'
  end
end
