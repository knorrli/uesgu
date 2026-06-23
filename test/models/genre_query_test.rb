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

  test 'listable includes a zero-usage canonical that an alias points at' do
    # The clean-spelled genre can sit at events_count 0 because the live event
    # carries the messy variant's raw token (e.g. "Death Metal Melodic" → "Melodic
    # Death Metal"). It only earns its place via the alias, so it must stay listed
    # so it doesn't vanish from the catalogue right after the merge.
    canonical = genre(name: 'melodic-death-metal', events_count: 0)
    aliased = genre(name: 'death-metal-melodic', events_count: 1)
    aliased.merge_into!(canonical)

    names = Genre.listable.pluck(:name)

    assert_includes names, canonical.name, 'a zero-usage canonical with an alias stays listed'
    assert_includes names, aliased.name, 'the alias stays listed via its own taggings'
  end

  # --- Prose mining (names_in_prose / prose_mining_index) ---------------------
  # The ingest-time match-only miner: find KNOWN genre names in dropped
  # description prose, mint nothing. Synthetic taxonomy only.

  test 'names_in_prose matches a known genre named in prose' do
    Genre.create!(name: 'Zorptronic')
    index = Genre.prose_mining_index

    assert_equal ['Zorptronic'], Genre.names_in_prose('a night of pure zorptronic energy', index)
  end

  test 'names_in_prose returns the stored display spelling, not the prose casing' do
    Genre.create!(name: 'Zorptronic')

    assert_equal ['Zorptronic'], Genre.names_in_prose('ZORPTRONIC all night', Genre.prose_mining_index)
  end

  test 'names_in_prose folds spelling variants like the genre filter' do
    Genre.create!(name: 'Wub Core') # fingerprint "wubcore"
    index = Genre.prose_mining_index

    # multi-word window and hyphen variant both collapse to the stored spelling
    assert_equal ['Wub Core'], Genre.names_in_prose('expect some wub core tonight', index)
    assert_equal ['Wub Core'], Genre.names_in_prose('expect some wub-core tonight', index)
  end

  test 'names_in_prose is greedy: the longest window wins, no redundant sub-tags' do
    Genre.create!(name: 'Wub')
    Genre.create!(name: 'Wub Core')

    assert_equal ['Wub Core'], Genre.names_in_prose('heavy wub core set', Genre.prose_mining_index)
  end

  test 'names_in_prose respects word boundaries (no sub-word hits)' do
    Genre.create!(name: 'Zorp')
    index = Genre.prose_mining_index

    assert_empty Genre.names_in_prose('zorptronic and zorps and bezorp', index)
    assert_equal ['Zorp'], Genre.names_in_prose('a zorp night', index)
  end

  test 'names_in_prose mints nothing and matches only the known vocabulary' do
    Genre.create!(name: 'Zorptronic')
    index = Genre.prose_mining_index

    assert_no_difference -> { Genre.count } do
      result = Genre.names_in_prose('zorptronic meets some flarejazz', index)
      assert_equal ['Zorptronic'], result # flarejazz is unknown → not mined
    end
  end

  test 'prose_mining_index excludes blocked genres' do
    blocked = Genre.create!(name: 'Wubnoise')
    blocked.block!

    refute_includes Genre.prose_mining_index.keys, blocked.fingerprint
  end

  test 'prose_mining_index excludes the everyday-word stoplist' do
    word = Genre::PROSE_MINING_STOPWORDS.first
    Genre.create!(name: word) # a real genre, but too ambiguous to mine from prose
    index = Genre.prose_mining_index

    refute_includes index.keys, Genre.fingerprint_for(word)
    assert_empty Genre.names_in_prose("the #{word} was packed", index)
  end

  test 'prose_mining_index includes alias raw names so they resolve at filter time' do
    canonical = Genre.create!(name: 'Zorptronic')
    aliased = Genre.create!(name: 'Zorptronik')
    aliased.merge_into!(canonical)
    index = Genre.prose_mining_index

    # the alias keeps its own fingerprint/name; mining "zorptronik" attaches the
    # raw token, which the filter resolves to Zorptronic at query time.
    assert_equal ['Zorptronik'], Genre.names_in_prose('pure zorptronik vibes', index)
  end
end
