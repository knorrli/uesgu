class AddHighlightInFeedToSavedFilters < ActiveRecord::Migration[8.1]
  def change
    # Per-filter "Im Feed hervorheben" toggle (#66). Defaults ON so existing
    # saved filters keep highlighting exactly as before; a broad scope-filter
    # gets unticked once by its owner.
    add_column :saved_filters, :highlight_in_feed, :boolean, default: true, null: false
  end
end
