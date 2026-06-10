require 'db_test_helper'

# Locks the curation-dashboard projections in EventTagStatsPresenter: location and
# style tag lookups scoped to Event taggings, and the genre buckets (in-use,
# assigned, unassigned, ignored). Synthetic names only.
class EventTagStatsPresenterTest < ActiveSupport::TestCase
  setup { @presenter = EventTagStatsPresenter.new }

  test 'location_tags returns only location-context tags on events' do
    event = event_with_genres('some-genre')
    event.update!(location_list: ['Invented Venue'])

    names = @presenter.location_tags.map(&:name)

    assert_includes names, 'Invented Venue'
    refute_includes names, 'some-genre', 'genre tags must not leak into locations'
  end

  test 'style_tags returns only style-context tags on events' do
    event = event_with_genres('another-genre')
    event.update!(style_list: ['Invented Style'])

    names = @presenter.style_tags.map(&:name)

    assert_includes names, 'Invented Style'
    refute_includes names, 'another-genre'
  end

  test 'genre_tags includes in-use genres and excludes dormant ones' do
    used = genre(name: 'used', events_count: 4)
    genre(name: 'dormant', events_count: 0)

    names = @presenter.genre_tags.pluck(:name)

    assert_includes names, used.name
    refute_includes names, 'dormant'
  end

  test 'assigned_genre_tags lists only in-use genres mapped to a style' do
    mapped = genre(name: 'mapped', events_count: 2, styles: [style])
    genre(name: 'bare', events_count: 2)

    names = @presenter.assigned_genre_tags.pluck(:name)

    assert_includes names, mapped.name
    refute_includes names, 'bare'
  end

  test 'unassigned_genre_tags lists the in-use, undisposed, unmapped queue' do
    queued = genre(name: 'queued', events_count: 7)
    genre(name: 'mapped2', events_count: 7, styles: [style])

    names = @presenter.unassigned_genre_tags.pluck(:name)

    assert_includes names, queued.name
    refute_includes names, 'mapped2'
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
