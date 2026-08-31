class AddGenreExclusion < ActiveRecord::Migration[8.0]
  def change
    add_column :genres, :excluded_at, :datetime
    add_index :genres, :excluded_at

    add_column :events, :hidden, :boolean, default: false, null: false
    add_index :events, :hidden
  end
end
