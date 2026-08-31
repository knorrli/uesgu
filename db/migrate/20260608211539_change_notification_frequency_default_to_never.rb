class ChangeNotificationFrequencyDefaultToNever < ActiveRecord::Migration[8.0]
  def change
    change_column_default :users, :notification_frequency, from: "weekly", to: "never"
  end
end
