class AddCancelledAtToEvents < ActiveRecord::Migration[8.0]
  def change
    # Soft, reversible cancellation flag. The event stays visible (with a marker);
    # scrapers re-derive it each run from the source, so no backfill is needed.
    add_column :events, :cancelled_at, :datetime
  end
end
