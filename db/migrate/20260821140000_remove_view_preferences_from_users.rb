class RemoveViewPreferencesFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :events_view, :string
    remove_column :users, :saved_events_view, :string
  end
end
