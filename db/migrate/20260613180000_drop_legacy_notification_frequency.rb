class DropLegacyNotificationFrequency < ActiveRecord::Migration[8.0]
  def change
    remove_column :users, :notification_frequency, :string, default: "never", null: false
    remove_column :users, :last_notified_at, :datetime
  end
end
