class AddCanonicalToGenres < ActiveRecord::Migration[8.0]
  def change
    add_reference :genres, :canonical, foreign_key: { to_table: :genres }, null: true, index: true
    add_check_constraint :genres, 'canonical_id IS NULL OR canonical_id <> id',
                         name: 'genres_canonical_not_self'
  end
end
