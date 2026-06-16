class AddDiscardedCountToScrapeResults < ActiveRecord::Migration[8.0]
  def change
    # How many events this scraper run filtered out via discard rules — a
    # safeguard signal (a spike flags an over-broad rule suppressing a venue).
    add_column :scrape_results, :discarded_count, :integer, default: 0, null: false
  end
end
