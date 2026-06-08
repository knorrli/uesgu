class ChangeNotificationFrequencyDefaultToNever < ActiveRecord::Migration[8.0]
  # Notifications are opt-in: a new account defaults to no notifications until the
  # user explicitly chooses a cadence. Existing rows keep their current value.
  def change
    change_column_default :users, :notification_frequency, from: "weekly", to: "never"
  end
end
