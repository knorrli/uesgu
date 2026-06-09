class RenameGenreDispositions < ActiveRecord::Migration[8.0]
  def change
    # Align the disposition column names with their UI labels (ignored / hidden /
    # blocked). The blocklist already landed as blocked_at; this renames the older
    # two. rename_column also renames the conventionally-named indexes.
    rename_column :genres, :dismissed_at, :ignored_at
    rename_column :genres, :excluded_at, :hidden_at
  end
end
