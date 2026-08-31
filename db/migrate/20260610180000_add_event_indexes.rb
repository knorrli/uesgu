class AddEventIndexes < ActiveRecord::Migration[8.0]
  def change
    add_index :events, :start_date

    add_index :events, :url, unique: true

    add_foreign_key :genres_styles, :genres, on_delete: :cascade
    add_foreign_key :genres_styles, :styles, on_delete: :cascade
  end
end
