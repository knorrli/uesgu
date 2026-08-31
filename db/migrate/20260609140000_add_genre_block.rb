class AddGenreBlock < ActiveRecord::Migration[8.0]
  def change
    add_column :genres, :blocked_at, :datetime
    add_index :genres, :blocked_at
  end
end
