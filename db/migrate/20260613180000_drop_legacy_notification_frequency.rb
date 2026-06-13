# Retire the legacy frequency-digest system: notifications are now driven entirely
# by NotificationRule (saved filter + schedule), so the per-user global frequency
# and its cursor are gone.
class DropLegacyNotificationFrequency < ActiveRecord::Migration[8.0]
  def change
    remove_column :users, :notification_frequency, :string, default: "never", null: false
    remove_column :users, :last_notified_at, :datetime
  end
end
