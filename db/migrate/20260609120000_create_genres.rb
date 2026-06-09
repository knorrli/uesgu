class CreateGenres < ActiveRecord::Migration[8.0]
  def change
    create_table :genres do |t|
      t.string :name, null: false
      # When set, the genre has been intentionally reviewed and left unmapped
      # ("won't fix") — it drops out of the assignment queue but stays a real
      # genre on its events. Distinct from a discarded/deleted tag.
      t.datetime :dismissed_at
      # Cached count of events carrying this genre, refreshed by Genre.reconcile!.
      # Drives the queue ordering (highest-impact genres first).
      t.integer :events_count, null: false, default: 0
      t.timestamps
    end
    add_index :genres, 'lower(name)', unique: true, name: 'index_genres_on_lower_name'
    add_index :genres, :dismissed_at

    # The genre → style mapping is now a plain many-to-many between two
    # first-class concepts, replacing the old "a Style is tagged with genre
    # strings" indirection.
    create_join_table :genres, :styles do |t|
      t.index %i[genre_id style_id], unique: true
      t.index :style_id
    end
  end
end
