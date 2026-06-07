class AddAccountsToUsers < ActiveRecord::Migration[8.0]
  def up
    add_column :users, :username, :string
    add_column :users, :admin, :boolean, default: false, null: false
    add_column :users, :notification_frequency, :string, default: "weekly", null: false
    add_column :users, :last_notified_at, :datetime

    # Email is now optional (only needed for the email channel / password reset).
    change_column_null :users, :email_address, true

    # Backfill existing accounts (the original admin) before enforcing NOT NULL.
    execute <<~SQL.squish
      UPDATE users
      SET username = split_part(email_address, '@', 1),
          admin = true
      WHERE username IS NULL
    SQL

    change_column_null :users, :username, false
    add_index :users, :username, unique: true
  end

  def down
    remove_index :users, :username
    remove_column :users, :username
    remove_column :users, :admin
    remove_column :users, :notification_frequency
    remove_column :users, :last_notified_at
    change_column_null :users, :email_address, false
  end
end
