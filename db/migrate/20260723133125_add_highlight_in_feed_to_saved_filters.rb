class AddHighlightInFeedToSavedFilters < ActiveRecord::Migration[8.1]
  def change
    add_column :saved_filters, :highlight_in_feed, :boolean, default: true, null: false
  end
end
