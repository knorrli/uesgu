require 'db_test_helper'

# Locks GenreTreeSeed: it builds the genre tree from a parsed seed hash, applies
# dispositions + aliases, is idempotent, and leaves out-of-seed genres untouched.
# Synthetic taxonomy only (invented names), matching db/genres.yml's shape but
# never its content.
class GenreTreeSeedTest < ActiveSupport::TestCase
  SEED = {
    'genres' => [
      { 'name' => 'Zorprock', 'children' => [
        { 'name' => 'Zorppunk', 'children' => %w[Zorpcrust Zorphardcore] },
        'Zorpgaze'
      ] },
      { 'name' => 'Zorpwave', 'children' => %w[Zorptechno] }
    ],
    'hidden'  => %w[Zorpquiz],
    'blocked' => %w[Zorpnoise],
    'ignored' => %w[Zorpfest],
    'aliases' => { 'Zorpwave' => %w[Zorpwaev] }
  }.freeze

  def find(name)
    Genre.find_by(fingerprint: Genre.fingerprint_for(name))
  end

  test 'builds the nested tree from the seed' do
    GenreTreeSeed.import(SEED)

    assert_nil find('Zorprock').parent_id, 'a top-level genre is a root'
    assert_equal find('Zorprock').id, find('Zorppunk').parent_id
    assert_equal find('Zorppunk').id, find('Zorpcrust').parent_id
    assert_equal find('Zorppunk').id, find('Zorphardcore').parent_id
    assert_equal find('Zorprock').id, find('Zorpgaze').parent_id
    # The whole Zorprock subtree, reached by descendant expansion.
    names = Genre.where(id: find('Zorprock').descendant_ids).pluck(:name)
    assert_equal %w[Zorpcrust Zorpgaze Zorphardcore Zorppunk], names.sort
  end

  test 'applies dispositions and aliases' do
    GenreTreeSeed.import(SEED)

    assert find('Zorpquiz').hidden?
    assert find('Zorpnoise').blocked?
    assert find('Zorpfest').ignored?
    assert find('Zorpwaev').aliased?, 'an alias variant points at its canonical'
    assert_equal find('Zorpwave').id, find('Zorpwaev').canonical_id
  end

  test 're-running converges (idempotent)' do
    GenreTreeSeed.import(SEED)
    before = Genre.count
    placed_before = Genre.placed.pluck(:id, :parent_id).sort

    GenreTreeSeed.import(SEED)

    assert_equal before, Genre.count, 'no duplicate rows on re-run'
    assert_equal placed_before, Genre.placed.pluck(:id, :parent_id).sort, 'placements stable'
  end

  test 'leaves genres not named in the seed untouched (they stay unplaced)' do
    # A real tagging so reconcile! (run by import) registers it and keeps it in_use.
    event_with_genres('Zorpstray')

    GenreTreeSeed.import(SEED)

    stray = find('Zorpstray')
    assert_nil stray.parent_id
    assert_includes Genre.unplaced.pluck(:id), stray.id
  end

  test 'a disposition wins over a tree placement for the same genre' do
    seed = { 'genres' => [{ 'name' => 'Zorptop', 'children' => %w[Zorpdual] }],
             'hidden' => %w[Zorpdual] }

    GenreTreeSeed.import(seed)

    assert_nil find('Zorpdual').parent_id, 'the disposition detached it from the tree'
    assert find('Zorpdual').hidden?
  end
end
