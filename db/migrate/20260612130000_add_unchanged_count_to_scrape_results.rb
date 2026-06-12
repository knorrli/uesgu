class AddUnchangedCountToScrapeResults < ActiveRecord::Migration[8.0]
  def change
    # Re-scraped events whose data was identical. Split out from updated_count so
    # "updated" means the data actually changed (a re-scrape touches every event
    # otherwise, making the number meaningless).
    add_column :scrape_results, :unchanged_count, :integer, null: false, default: 0
  end
end
