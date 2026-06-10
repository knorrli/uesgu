class AddCanonicalToGenres < ActiveRecord::Migration[8.0]
  # A genre may point at a canonical genre it is an alias of (e.g. "Elektronik" →
  # "Electronic") — semantic merges that the fingerprint can't catch. Resolved at
  # ingest and used by the admin merge UI. Schema only; the merging itself
  # (re-pointing taggings, folding counts) is done by Genre#merge_into! and seeded
  # via the genres:import_aliases rake task.
  def change
    add_reference :genres, :canonical, foreign_key: { to_table: :genres }, null: true, index: true
    add_check_constraint :genres, 'canonical_id IS NULL OR canonical_id <> id',
                         name: 'genres_canonical_not_self'
  end
end
