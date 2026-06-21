require_relative '../../db_test_helper'

# Mechanics of cross-source dedup. Uses real tracked venues ("Kofmehl" for the
# PETZI/bespoke cases, "Dachstock" for the OLE cases) because Dedup processes
# Petzi::VENUES + the OLE source venues; genres are invented (taxonomy rule).
# Source authority is read from data_source (OLE > PETZI > bespoke).
class Scrapers::DedupTest < ActiveSupport::TestCase
  FUTURE = Date.current + 10

  def petzi_event(title:, date: FUTURE, genres: [], venue: 'Kofmehl')
    make(title:, date:, genres:, venue:, source: 'Petzi')
  end

  def bespoke_event(title:, date: FUTURE, genres: [], venue: 'Kofmehl')
    make(title:, date:, genres:, venue:, source: venue) # bespoke stamps its class name
  end

  def ole_event(title:, date: FUTURE, genres: [], venue: 'Dachstock')
    make(title:, date:, genres:, venue:, source: "OLE:#{venue}")
  end

  def make(title:, date:, genres:, venue:, source:)
    n = TaxonomyFixtures.next_seq
    e = event(title:, start_date: date, url: "https://example.test/#{n}",
              location_list: [venue, 'Solothurn', 'SO'])
    e.data_source = source
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

  # OLE is the PREFERRED source (venue-published, links to the venue's own page),
  # so where it overlaps a PETZI show the PETZI copy folds onto the OLE canonical
  # — not the other way round — and OLE stays the single visible listing. Genres ∪
  # onto the OLE canonical, so PETZI's genres are not lost.
  test 'an OLE event overlapping a PETZI show is canonical; PETZI folds onto it' do
    ole = make(title: 'Shared Headliner', date: FUTURE, genres: ['ole-genre'],
               venue: 'Dachstock', source: 'OLE:Dachstock')
    p   = make(title: 'Shared Headliner', date: FUTURE, genres: ['petzi-genre'],
               venue: 'Dachstock', source: 'Petzi')

    Scrapers::Dedup.run

    assert_equal ole.id, p.reload.canonical_event_id, 'PETZI copy points at the OLE canonical'
    assert_nil ole.reload.canonical_event_id, 'OLE stays canonical'
    refute_includes Event.visible, p, 'PETZI duplicate is hidden, not a second listing'
    assert_includes Event.visible, ole
    genres = ole.reload.genre_list.map(&:downcase)
    assert_includes genres, 'ole-genre'
    assert_includes genres, 'petzi-genre', 'PETZI genres union onto the OLE canonical'
  end

  # The reported bug: a venue with BOTH an OLE feed and a bespoke HTML scraper but
  # no PETZI listing for the show. The old dedup only linked bespoke→PETZI, so the
  # two non-PETZI copies were never compared and both showed. Now OLE outranks
  # bespoke and absorbs it directly.
  test 'an OLE event absorbs a matching bespoke show with no PETZI listing' do
    ole = ole_event(title: 'Reitschule Fest', venue: 'Dachstock', genres: ['ole-genre'])
    b   = bespoke_event(title: 'Reitschule Fest', venue: 'Dachstock', genres: ['bespoke-genre'])

    Scrapers::Dedup.run

    assert_equal ole.id, b.reload.canonical_event_id, 'bespoke copy points at the OLE canonical'
    assert_nil ole.reload.canonical_event_id, 'OLE stays canonical'
    refute_includes Event.visible, b, 'bespoke duplicate is hidden'
    assert_includes Event.visible, ole
    assert_includes ole.reload.genre_list.map(&:downcase), 'bespoke-genre', 'genres union onto OLE'
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
