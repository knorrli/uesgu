class CreateScrapeResults < ActiveRecord::Migration[8.0]
  def change
    create_table :scrape_results do |t|
      t.references :scrape_run, null: false, foreign_key: { on_delete: :cascade }
      t.string :scraper, null: false
      # ok = wrote >=1 event; empty = ran clean but wrote none (silent
      # regression); failed = raised out of the scraper (site down etc.).
      t.string :status, null: false
      t.datetime :started_at
      t.integer :duration_ms
      t.integer :rows_seen, null: false, default: 0
      t.integer :created_count, null: false, default: 0
      t.integer :updated_count, null: false, default: 0
      t.integer :skipped_count, null: false, default: 0
      t.string :error_class
      t.text :error_message
      t.timestamps
    end
    add_index :scrape_results, %i[scrape_run_id scraper]
    add_index :scrape_results, :scraper
  end
end
