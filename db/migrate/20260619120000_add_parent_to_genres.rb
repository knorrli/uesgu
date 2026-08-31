class AddParentToGenres < ActiveRecord::Migration[8.0]
  def change
    add_reference :genres, :parent, foreign_key: { to_table: :genres }, null: true, index: true
    add_check_constraint :genres, 'parent_id IS NULL OR parent_id <> id',
                         name: 'genres_parent_not_self'
  end
end
