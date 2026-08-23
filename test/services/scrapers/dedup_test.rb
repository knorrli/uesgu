require_relative "../../db_test_helper"

# Mechanics of cross-source dedup. Uses real tracked venues ("Kofmehl" for the
# PETZI/bespoke cases, "Dachstock" for the OLE cases) because Dedup processes
# every consume venue in the registry (+ the PETZI members); genres are
# invented (taxonomy rule). Source authority is read from data_source
# (OLE > bespoke > PETZI): we rank by which copy links most directly to the
# venue, so PETZI is the last resort. Same-source pairs fold only on the
# identical start TIME (a double-post), never across different hours (a
# same-titled second happening).
class Scrapers::DedupTest < ActiveSupport::TestCase
  FUTURE = Date.current + 10

  def petzi_event(title:, date: FUTURE, genres: [], venue: "Kofmehl")
    make(title:, date:, genres:, venue:, source: "Petzi")
  end

  def bespoke_event(title:, date: FUTURE, genres: [], venue: "Kofmehl")
    make(title:, date:, genres:, venue:, source: venue) # bespoke stamps its class name
  end

  def ole_event(title:, date: FUTURE, genres: [], venue: "Dachstock")
    make(title:, date:, genres:, venue:, source: "OLE:#{venue}")
  end

  # A contributor's capture. No url — which is half of why it ranks below even PETZI
  # — so it cannot go through `make`, whose url is the scrapers' upsert key.
  def captured_event(title:, date: FUTURE, genres: [], venue: "Kofmehl",
                     locality: "Solothurn", canton: "SO", time: nil)
    e = Event.new(title:, start_date: date, start_time: time,
                  data_source: EventCapture::Creator::DATA_SOURCE,
                  location_list: [venue, locality, canton])
    e.genre_list = genres if genres.any?
    e.save!
    e
  end

  def make(title:, date:, genres:, venue:, source:, time: nil)
    n = TaxonomyFixtures.next_seq
    e = event(title:, start_date: date, url: "https://example.test/#{n}",
              location_list: [venue, "Solothurn", "SO"])
    e.data_source = source
    e.start_time = time if time
    e.genre_list = genres if genres.any?
    e.save!
    e
  end

  test "a matching PETZI event folds onto the bespoke canonical (bespoke links direct)" do
    b = bespoke_event(title: "Malevolence")
    p = petzi_event(title: "Malevolence")

    Scrapers::Dedup.run

    assert_equal b.id, p.reload.canonical_event_id
    assert_nil b.reload.canonical_event_id, "bespoke event stays canonical"
    assert_includes Event.visible, b
    refute_includes Event.visible, p, "PETZI duplicate is suppressed"
    assert_equal [p], b.duplicate_events.to_a
  end

  test "bookmarks on a duplicate survive (it is hidden, never deleted)" do
    bespoke_event(title: "Survivor")          # the canonical
    p = petzi_event(title: "Survivor")        # the duplicate (PETZI ranks last)
    u = user
    EventSave.create!(user: u, event: p)

    Scrapers::Dedup.run

    assert EventSave.exists?(user: u, event: p), "bookmark preserved"
    assert Event.exists?(p.id), "duplicate not deleted"
  end

  test "duplicate's genres are unioned onto the canonical" do
    b = bespoke_event(title: "Union Show", genres: ["zorprock-canon"])  # canonical
    petzi_event(title: "Union Show", genres: ["zorpmetal-dup"])         # duplicate

    Scrapers::Dedup.run

    genres = b.reload.genre_list.map(&:downcase)
    assert_includes genres, "zorprock-canon"
    assert_includes genres, "zorpmetal-dup"
  end

  test "a bespoke event PETZI does not list stays canonical and visible" do
    petzi_event(title: "Some Other Band")
    b = bespoke_event(title: "Totally Unrelated Act")

    Scrapers::Dedup.run

    assert_nil b.reload.canonical_event_id
    assert_includes Event.visible, b
  end

  test "same title on a different date does not match" do
    petzi_event(title: "Same Title", date: FUTURE)
    b = bespoke_event(title: "Same Title", date: FUTURE + 1)

    Scrapers::Dedup.run

    assert_nil b.reload.canonical_event_id
  end

  test "a truncated club title matches the full PETZI lineup (subset rule)" do
    b = bespoke_event(title: "Darkside")
    p = petzi_event(title: "Darkside: PYTHIUS, COPPA, DAYNI, MC Resc")

    Scrapers::Dedup.run

    assert_equal b.id, p.reload.canonical_event_id
  end

  test "a stale canonical link resets when PETZI no longer lists the show" do
    other = petzi_event(title: "Unrelated Headliner")
    b = bespoke_event(title: "Orphaned Show")
    b.update_column(:canonical_event_id, other.id) # stale link from a prior run

    Scrapers::Dedup.run

    assert_nil b.reload.canonical_event_id, "no title match → link cleared, event re-surfaces"
    assert_includes Event.visible, b
  end

  test "an admin-pinned merge is not undone by a later dedup" do
    p = petzi_event(title: "Pinned Canonical")
    b = bespoke_event(title: "Drifted Title The Matcher Misses")
    b.merge_into!(p) # manual merge + pin

    Scrapers::Dedup.run

    assert_equal p.id, b.reload.canonical_event_id, "pinned link survives"
    refute_includes Event.visible, b
  end

  test "an admin-pinned merge still feeds its genres to the canonical" do
    p = petzi_event(title: "Pinned Genres", genres: ["zorpcanon-x"])
    b = bespoke_event(title: "Totally Different But Manually Merged", genres: ["zorpdup-x"])
    b.merge_into!(p)

    Scrapers::Dedup.run

    genres = p.reload.genre_list.map(&:downcase)
    assert_includes genres, "zorpcanon-x"
    assert_includes genres, "zorpdup-x"
  end

  test "an admin-pinned standalone is not re-merged by dedup" do
    p = petzi_event(title: "Identical Title")
    b = bespoke_event(title: "Identical Title") # would auto-match
    b.mark_standalone! # admin says: NOT a duplicate, pin it

    Scrapers::Dedup.run

    assert_nil b.reload.canonical_event_id, "pinned standalone stays split"
    assert_includes Event.visible, b
  end

  # OLE is the PREFERRED source (venue-published, links to the venue's own page),
  # so where it overlaps a PETZI show the PETZI copy folds onto the OLE canonical
  # — not the other way round — and OLE stays the single visible listing. Genres ∪
  # onto the OLE canonical, so PETZI's genres are not lost.
  test "an OLE event overlapping a PETZI show is canonical; PETZI folds onto it" do
    ole = make(title: "Shared Headliner", date: FUTURE, genres: ["ole-genre"],
               venue: "Dachstock", source: "OLE:Dachstock")
    p   = make(title: "Shared Headliner", date: FUTURE, genres: ["petzi-genre"],
               venue: "Dachstock", source: "Petzi")

    Scrapers::Dedup.run

    assert_equal ole.id, p.reload.canonical_event_id, "PETZI copy points at the OLE canonical"
    assert_nil ole.reload.canonical_event_id, "OLE stays canonical"
    refute_includes Event.visible, p, "PETZI duplicate is hidden, not a second listing"
    assert_includes Event.visible, ole
    genres = ole.reload.genre_list.map(&:downcase)
    assert_includes genres, "ole-genre"
    assert_includes genres, "petzi-genre", "PETZI genres union onto the OLE canonical"
  end

  # The reported bug: a venue with BOTH an OLE feed and a bespoke HTML scraper but
  # no PETZI listing for the show. The old dedup only linked bespoke→PETZI, so the
  # two non-PETZI copies were never compared and both showed. Now OLE outranks
  # bespoke and absorbs it directly.
  test "an OLE event absorbs a matching bespoke show with no PETZI listing" do
    ole = ole_event(title: "Reitschule Fest", venue: "Dachstock", genres: ["ole-genre"])
    b   = bespoke_event(title: "Reitschule Fest", venue: "Dachstock", genres: ["bespoke-genre"])

    Scrapers::Dedup.run

    assert_equal ole.id, b.reload.canonical_event_id, "bespoke copy points at the OLE canonical"
    assert_nil ole.reload.canonical_event_id, "OLE stays canonical"
    refute_includes Event.visible, b, "bespoke duplicate is hidden"
    assert_includes Event.visible, ole
    assert_includes ole.reload.genre_list.map(&:downcase), "bespoke-genre", "genres union onto OLE"
  end

  # A venue double-posting one show on its aggregator: the same Salsa night under two
  # Bewegungsmelder post ids, so two distinct upsert keys land two events from ONE
  # source. The NEWER copy wins the canonical, because for a re-keyed strand — a
  # scraper whose URL scheme changed — the newer row is the one with the working link.
  test "a same-source double-post folds onto the newest copy" do
    showtime = Time.zone.local(FUTURE.year, FUTURE.month, FUTURE.day, 19, 0)
    older = make(title: "Tanzen im Schlosshof | Zorpsalsa", date: FUTURE, genres: [],
                 venue: "Kulturhof Schloss Köniz", source: "OLE:Bewegungsmelder", time: showtime)
    newer = make(title: "Tanzen im Schlosshof | Zorpsalsa", date: FUTURE, genres: [],
                 venue: "Kulturhof Schloss Köniz", source: "OLE:Bewegungsmelder", time: showtime)

    Scrapers::Dedup.run

    assert_equal newer.id, older.reload.canonical_event_id, "older double-post folds onto the newer"
    assert_nil newer.reload.canonical_event_id, "newer copy stays canonical"
    assert_includes Event.visible, newer
    refute_includes Event.visible, older
  end

  # One title, one day, two HOURS: a 15:00 workshop and a 20:00 concert are two real
  # happenings from one source, and must both stay.
  test "same-titled shows at different hours are distinct happenings, not duplicates" do
    workshop = make(title: "Tradition in Zorpbewegung", date: FUTURE, genres: [],
                    venue: "ONO", source: "Ono",
                    time: Time.zone.local(FUTURE.year, FUTURE.month, FUTURE.day, 15, 0))
    concert  = make(title: "Tradition in Zorpbewegung", date: FUTURE, genres: [],
                    venue: "ONO", source: "Ono",
                    time: Time.zone.local(FUTURE.year, FUTURE.month, FUTURE.day, 20, 0))

    Scrapers::Dedup.run

    assert_nil workshop.reload.canonical_event_id
    assert_nil concert.reload.canonical_event_id
    assert_includes Event.visible, workshop
    assert_includes Event.visible, concert
  end

  # A capture is always NEWER than the scraped copy it duplicates, and within one
  # rank the newest wins — so ranking it explicitly is the whole point: unranked it
  # falls in beside the bespoke scrapers and takes the canonical off a copy that
  # links to the venue's own page.
  test "a captured event folds onto the scraped copy, newer though it is" do
    b = bespoke_event(title: "Zorpcore Allstars")
    c = captured_event(title: "Zorpcore Allstars")

    Scrapers::Dedup.run

    assert_equal b.id, c.reload.canonical_event_id, "the capture folds onto the scraped copy"
    assert_nil b.reload.canonical_event_id, "the scraped copy stays canonical"
    assert_includes Event.visible, b
    refute_includes Event.visible, c
    assert_equal b.url, Event.visible.find(b.id).url, "the visible copy keeps its link"
  end

  test "a captured event ranks below even PETZI" do
    p = petzi_event(title: "Zorpwave Nacht")
    c = captured_event(title: "Zorpwave Nacht")

    Scrapers::Dedup.run

    assert_equal p.id, c.reload.canonical_event_id
    assert_nil p.reload.canonical_event_id
  end

  # What a capture is FOR: the description and genres a contributor read off the
  # poster reaching the listing that lacks them. Genres already ride the existing
  # union; nothing else does yet.
  test "a captured duplicate's genres accumulate onto the scraped canonical" do
    b = bespoke_event(title: "Zorpjazz Sextet", genres: ["scraped-genre"])
    captured_event(title: "Zorpjazz Sextet", genres: ["captured-genre"])

    Scrapers::Dedup.run

    assert_includes b.reload.genre_list.map(&:downcase), "captured-genre"
    assert_includes b.genre_list.map(&:downcase), "scraped-genre"
  end

  # A captured place is the registry's complement, so it appears in no venue list
  # the sweep walked before — and two contributors shooting the same poster is
  # exactly where a duplicate lands. Neither carries a time, which is what a
  # same-source pair needs to be one double-post rather than two happenings.
  test "captures at a captured place are deduped at all" do
    venue = place.name
    first  = captured_event(title: "Zorpfolk im Hof", venue: venue, locality: "Zorpwil", canton: "BE")
    second = captured_event(title: "Zorpfolk im Hof", venue: venue, locality: "Zorpwil", canton: "BE")

    Scrapers::Dedup.run

    assert_equal second.id, first.reload.canonical_event_id, "the older capture folds onto the newer"
    assert_nil second.reload.canonical_event_id
    refute_includes Event.visible, first
    assert_includes Event.visible, second
  end

  test "past events are left untouched" do
    past = Date.current - 5
    p = petzi_event(title: "Past Show", date: past)
    b = bespoke_event(title: "Past Show", date: past)
    b.update_column(:canonical_event_id, nil)

    Scrapers::Dedup.run

    assert_nil b.reload.canonical_event_id, "past pair not processed"
  end
end
