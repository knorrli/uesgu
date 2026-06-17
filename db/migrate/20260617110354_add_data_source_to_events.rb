class AddDataSourceToEvents < ActiveRecord::Migration[8.0]
  def change
    # Which scraper produced this row (e.g. "Petzi", "Kofmehl"). Each event is
    # single-source (its url host determines origin); the cross-source merge is a
    # relationship between rows (canonical_event_id), not a blend within one — so a
    # per-row source is unambiguous and useful for admin dedup debugging.
    add_column :events, :data_source, :string
  end
end
