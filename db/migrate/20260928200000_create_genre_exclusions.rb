class CreateGenreExclusions < ActiveRecord::Migration[8.1]
  def change
    create_table :genre_exclusions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :genre, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :genre_exclusions, %i[user_id genre_id], unique: true
  end
end
