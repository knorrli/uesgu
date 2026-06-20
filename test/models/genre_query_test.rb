require 'db_test_helper'

# Locks Genre's class-level mechanics — ensure! (idempotent, fingerprint-keyed
# row creation), reconcile! (usage-count refresh from taggings),
# blocked_fingerprints (the blocklist) — and the curation scopes. Synthetic
# names only; genres are matched by fingerprint via the genre_for helper since
# ingest canonicalizes casing/spelling.
class GenreQueryTest < ActiveSupport::TestCase
  # --- Genre.ensure! ---------------------------------------------------------

  test 'ensure! creates a row per new name' do
    assert_difference -> { Genre.count }, 2 do
      Genre.ensure!(%w[zorptronic flarejazz])
    end
    assert genre_for('zorptronic')
    assert genre_for('flarejazz')
  end

  test 'ensure! is idempotent across calls' do
    Genre.ensure!(%w[wubcore])
    assert_no_difference -> { Genre.count } do
      Genre.ensure!(%w[wubcore])
    end
  end

  test 'ensure! does not duplicate a case variant of an existing genre' do
    Genre.create!(name: 'Glimmercore')
    assert_no_difference -> { Genre.count } do
      Genre.ensure!(%w[glimmercore GLIMMERCORE])
    end
  end

  # --- Genre.reconcile! ------------------------------------------------------

  test 'reconcile! sets events_count from the live genre taggings' do
    event_with_genres('zorptronic')
    event_with_genres('zorptronic', 'flarejazz')

    Genre.reconcile!

    assert_equal 2, genre_for('zorptronic').events_count
    assert_equal 1, genre_for('flarejazz').events_count
  end

  test 'reconcile! creates rows for newly-seen tag names' do
    event_with_genres('brand-new-genre')
    assert_not genre_for('brand-new-genre')

    Genre.reconcile!

    assert_equal 1, genre_for('brand-new-genre').events_count
  end

  test 'reconcile! zeroes the count for a genre no longer tagged anywhere' do
    event_with_genres('still-tagged') # keep the taggings table non-empty
    stale = genre(name: 'forgotten', events_count: 9)

    Genre.reconcile!

    assert_equal 0, stale.reload.events_count
    assert_equal 1, genre_for('still-tagged').events_count
  end

  test 'reconcile! zeroes stale counts even when nothing is tagged at all' do
    # Regression: with an empty taggings set the old `NOT IN (NULL)` matched no
    # rows, so phantom counts survived and genres stayed falsely "in use".
    stale = genre(name: 'orphan', events_count: 7)

    Genre.reconcile!

    assert_equal 0, stale.reload.events_count
  end

  # --- Genre.blocked_fingerprints --------------------------------------------

  test 'blocked_fingerprints returns the fingerprints of only blocked genres' do
    blocked = Genre.create!(name: 'NoiseTag')
    blocked.block!
    genre(name: 'kept') # un-blocked, must not appear

    fingerprints = Genre.blocked_fingerprints

    assert_kind_of Set, fingerprints
    assert_includes fingerprints, Genre.fingerprint_for('NoiseTag')
    refute(fingerprints.any? { |fp| fp.start_with?('kept') })
  end

  # --- scopes ----------------------------------------------------------------

  test 'unplaced surfaces in-use genres with no parent and no disposition' do
    queued = genre(name: 'queued', events_count: 5)
    root = genre(name: 'root', events_count: 5)
    placed = genre(name: 'placed', events_count: 5, parent: root)
    genre(name: 'dormant', events_count: 0) # not in use → excluded
    parked = genre(name: 'parked', events_count: 3)
    parked.ignore!

    names = Genre.unplaced.pluck(:name)

    assert_includes names, queued.name
    refute_includes names, placed.name # filed under a parent
    refute_includes names, root.name   # IS a parent (has a child) → a root, not unplaced
    refute_includes names, 'dormant'
    refute_includes names, parked.name
  end

  test 'placed includes only genres filed under a parent' do
    root = genre
    child = genre(parent: root)
    bare = genre

    names = Genre.placed.pluck(:name)

    assert_includes names, child.name
    refute_includes names, bare.name
  end

  test 'listable includes parked (disposed) genres even at zero usage' do
    blocked = genre(name: 'blocked-zero', events_count: 0)
    blocked.block! # blocked genres tag 0 events yet must stay listed
    used = genre(name: 'used', events_count: 1)
    genre(name: 'truly-dormant', events_count: 0) # excluded

    names = Genre.listable.pluck(:name)

    assert_includes names, blocked.name
    assert_includes names, used.name
    refute_includes names, 'truly-dormant'
  end
end
