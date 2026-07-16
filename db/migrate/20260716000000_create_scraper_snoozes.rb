class CreateScraperSnoozes < ActiveRecord::Migration[8.1]
  def change
    create_table :scraper_snoozes do |t|
      # The scraper's slug (demodulized class name, underscored) — the same
      # identity ScrapeResult#scraper uses. One live snooze per scraper.
      t.string :scraper, null: false
      t.datetime :snoozed_until, null: false

      t.timestamps
    end
    add_index :scraper_snoozes, :scraper, unique: true
  end
end
