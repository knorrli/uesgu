class AddSavedEventsViewToUsers < ActiveRecord::Migration[8.0]
  def change
    # Mirrors users.events_view: the saved-shows page remembers its own list /
    # calendar choice per account, independent of the main programme's view.
    add_column :users, :saved_events_view, :string
  end
end
