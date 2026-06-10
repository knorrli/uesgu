class AddEventIndexes < ActiveRecord::Migration[8.0]
  def change
    # The events index + calendar filter and order by start_date on every page
    # load (the root route); only :hidden was indexed before.
    add_index :events, :start_date

    # Scrapers upsert by url (find_or_initialize_by(url:)) on every run. A unique
    # index makes that lookup fast and the dedup race-safe against overlapping
    # runs. Run `rails events:dedupe_urls` first if the table has any duplicates.
    add_index :events, :url, unique: true

    # Cascade the HABTM join rows if a Genre or Style is ever hard-deleted, so a
    # raw delete can't leave orphaned genres_styles rows.
    add_foreign_key :genres_styles, :genres, on_delete: :cascade
    add_foreign_key :genres_styles, :styles, on_delete: :cascade
  end
end
