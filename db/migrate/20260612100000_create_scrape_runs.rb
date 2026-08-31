class CreateScrapeRuns < ActiveRecord::Migration[8.0]
  def change
    create_table :scrape_runs do |t|
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.string :status, null: false, default: 'running'
      t.integer :scrapers_total, null: false, default: 0
      t.integer :scrapers_ok, null: false, default: 0
      t.integer :scrapers_empty, null: false, default: 0
      t.integer :scrapers_failed, null: false, default: 0
      t.timestamps
    end
    add_index :scrape_runs, :started_at
  end
end
