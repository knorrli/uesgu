class RenameSkippedCountToErroredCount < ActiveRecord::Migration[8.0]
  # `skipped_count` is only ever incremented by Scrapers::Agent#record_failure —
  # i.e. it counts events that FAILED to parse/save, not rows the scraper
  # intentionally filtered out (that's skip_row?, which is uncounted). Rename it
  # to match what it means so the admin run detail reads as an error signal.
  def change
    rename_column :scrape_results, :skipped_count, :errored_count
  end
end
