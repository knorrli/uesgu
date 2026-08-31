class AddSavedEventsViewToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :saved_events_view, :string
  end
end
