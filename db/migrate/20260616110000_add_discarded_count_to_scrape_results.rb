class AddDiscardedCountToScrapeResults < ActiveRecord::Migration[8.0]
  def change
    add_column :scrape_results, :discarded_count, :integer, default: 0, null: false
  end
end
