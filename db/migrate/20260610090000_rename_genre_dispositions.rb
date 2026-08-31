class RenameGenreDispositions < ActiveRecord::Migration[8.0]
  def change
    rename_column :genres, :dismissed_at, :ignored_at
    rename_column :genres, :excluded_at, :hidden_at
  end
end
