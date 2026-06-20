# A nullable timestamp marking an event whose date moved after it was first
# listed — the sibling of cancelled_at. Re-derived from the source each scrape
# (a "verschoben"/"new date" marker) or set when the scraper observes the stored
# date itself move between sweeps; the UI shows a "rescheduled" badge beside the
# date, exactly like cancellations. Nullable, no index — same shape as cancelled_at
# (read via a small where.not scope, not a hot path).
class AddRescheduledAtToEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :rescheduled_at, :datetime
  end
end
