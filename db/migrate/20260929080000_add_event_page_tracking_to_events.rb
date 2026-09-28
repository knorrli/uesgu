class AddEventPageTrackingToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :event_page_checked_at, :datetime
    add_column :events, :aggregator_url, :string
    add_index :events, :aggregator_url
  end
end
