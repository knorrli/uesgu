class AddUnchangedCountToScrapeResults < ActiveRecord::Migration[8.0]
  def change
    add_column :scrape_results, :unchanged_count, :integer, null: false, default: 0
  end
end
