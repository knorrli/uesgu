class AddCalendarFeedTokenToUsers < ActiveRecord::Migration[8.0]
  def change
    # Bearer token for an unauthenticated, subscribable ICS feed of the user's
    # saved shows (like a calendar "secret address"). Null until the user opts in
    # by creating the link; regenerable to revoke an old one.
    add_column :users, :calendar_feed_token, :string
    add_index :users, :calendar_feed_token, unique: true
  end
end
