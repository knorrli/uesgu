class CreateGenres < ActiveRecord::Migration[8.0]
  def change
    create_table :genres do |t|
      t.string :name, null: false
      t.datetime :dismissed_at
      t.integer :events_count, null: false, default: 0
      t.timestamps
    end
    add_index :genres, 'lower(name)', unique: true, name: 'index_genres_on_lower_name'
    add_index :genres, :dismissed_at

    create_join_table :genres, :styles do |t|
      t.index %i[genre_id style_id], unique: true
      t.index :style_id
    end
  end
end
