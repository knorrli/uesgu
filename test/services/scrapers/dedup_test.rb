require_relative '../../db_test_helper'

# Mechanics of cross-source dedup. Uses a real tracked venue ("Kofmehl") because
# Dedup only processes Petzi::VENUES; genres are invented (taxonomy rule).
class Scrapers::DedupTest < ActiveSupport::TestCase
  FUTURE = Date.current + 10

  def petzi_event(title:, date: FUTURE, genres: [], venue: 'Kofmehl')
    make(title:, date:, genres:, venue:, host: 'www.petzi.ch')
  end

  def bespoke_event(title:, date: FUTURE, genres: [], venue: 'Kofmehl')
    make(title:, date:, genres:, venue:, host: 'kofmehl.example')
  end

  def make(title:, date:, genres:, venue:, host:)
    n = TaxonomyFixtures.next_seq
    e = event(title:, start_date: date, url: "https://#{host}/#{n}",
              location_list: [venue, 'Solothurn', 'SO'])
    e.genre_list = genres if genres.any?
    e.save!
    e
  end

  test 'a matching bespoke event is linked to the PETZI canonical and hidden from visible' do
    p = petzi_event(title: 'Malevolence')
    b = bespoke_event(title: 'Malevolence')

    Scrapers::Dedup.run

    assert_equal p.id, b.reload.canonical_event_id
    assert_nil p.reload.canonical_event_id, 'PETZI event stays canonical'
    assert_includes Event.visible, p
    refute_includes Event.visible, b, 'duplicate is suppressed'
    assert_equal [b], p.duplicate_events.to_a
  end

  test 'bookmarks on a duplicate survive (it is hidden, never deleted)' do
    p = petzi_event(title: 'Survivor')
    b = bespoke_event(title: 'Survivor')
    u = user
    EventSave.create!(user: u, event: b)

    Scrapers::Dedup.run

    assert EventSave.exists?(user: u, event: b), 'bookmark preserved'
    assert Event.exists?(b.id), 'duplicate not deleted'
  end

  test "duplicate's genres are unioned onto the canonical" do
    p = petzi_event(title: 'Union Show', genres: ['zorprock-canon'])
    bespoke_event(title: 'Union Show', genres: ['zorpmetal-dup'])

    Scrapers::Dedup.run

    genres = p.reload.genre_list.map(&:downcase)
    assert_includes genres, 'zorprock-canon'
    assert_includes genres, 'zorpmetal-dup'
  end

  test 'a bespoke event PETZI does not list stays canonical and visible' do
    petzi_event(title: 'Some Other Band')
    b = bespoke_event(title: 'Totally Unrelated Act')

    Scrapers::Dedup.run

    assert_nil b.reload.canonical_event_id
    assert_includes Event.visible, b
  end

  test 'same title on a different date does not match' do
    petzi_event(title: 'Same Title', date: FUTURE)
    b = bespoke_event(title: 'Same Title', date: FUTURE + 1)

    Scrapers::Dedup.run

    assert_nil b.reload.canonical_event_id
  end

  test 'a truncated club title matches the full PETZI lineup (subset rule)' do
    p = petzi_event(title: 'Darkside: PYTHIUS, COPPA, DAYNI, MC Resc')
    b = bespoke_event(title: 'Darkside')

    Scrapers::Dedup.run

    assert_equal p.id, b.reload.canonical_event_id
  end

  test 'a stale canonical link resets when PETZI no longer lists the show' do
    other = petzi_event(title: 'Unrelated Headliner')
    b = bespoke_event(title: 'Orphaned Show')
    b.update_column(:canonical_event_id, other.id) # stale link from a prior run

    Scrapers::Dedup.run

    assert_nil b.reload.canonical_event_id, 'no title match → link cleared, event re-surfaces'
    assert_includes Event.visible, b
  end

  test 'an admin-pinned merge is not undone by a later dedup' do
    p = petzi_event(title: 'Pinned Canonical')
    b = bespoke_event(title: 'Drifted Title The Matcher Misses')
    b.merge_into!(p) # manual merge + pin

    Scrapers::Dedup.run

    assert_equal p.id, b.reload.canonical_event_id, 'pinned link survives'
    refute_includes Event.visible, b
  end

  test 'an admin-pinned merge still feeds its genres to the canonical' do
    p = petzi_event(title: 'Pinned Genres', genres: ['zorpcanon-x'])
    b = bespoke_event(title: 'Totally Different But Manually Merged', genres: ['zorpdup-x'])
    b.merge_into!(p)

    Scrapers::Dedup.run

    genres = p.reload.genre_list.map(&:downcase)
    assert_includes genres, 'zorpcanon-x'
    assert_includes genres, 'zorpdup-x'
  end

  test 'an admin-pinned standalone is not re-merged by dedup' do
    p = petzi_event(title: 'Identical Title')
    b = bespoke_event(title: 'Identical Title') # would auto-match
    b.mark_standalone! # admin says: NOT a duplicate, pin it

    Scrapers::Dedup.run

    assert_nil b.reload.canonical_event_id, 'pinned standalone stays split'
    assert_includes Event.visible, b
  end

  test 'past events are left untouched' do
    past = Date.current - 5
    p = petzi_event(title: 'Past Show', date: past)
    b = bespoke_event(title: 'Past Show', date: past)
    b.update_column(:canonical_event_id, nil)

    Scrapers::Dedup.run

    assert_nil b.reload.canonical_event_id, 'past pair not processed'
  end
end
