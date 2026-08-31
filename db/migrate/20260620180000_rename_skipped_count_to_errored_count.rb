class RenameSkippedCountToErroredCount < ActiveRecord::Migration[8.0]
  def change
    rename_column :scrape_results, :skipped_count, :errored_count
  end
end
