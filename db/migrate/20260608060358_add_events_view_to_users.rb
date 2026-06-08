class AddEventsViewToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :events_view, :string
  end
end
