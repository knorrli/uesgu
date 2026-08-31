class RenameEnabledToNotifyInAppOnNotificationRules < ActiveRecord::Migration[8.0]
  def change
    rename_column :notification_rules, :enabled, :notify_in_app
  end
end
