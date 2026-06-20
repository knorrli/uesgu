# save/notify model v2: in-app is the master channel. The old `enabled` (a
# separate pause/notify switch) collapses into `notify_in_app` — the in-app digest
# is created exactly when it's on, and push/email require it (forced off otherwise).
class RenameEnabledToNotifyInAppOnNotificationRules < ActiveRecord::Migration[8.0]
  def change
    # rename_column also regenerates the convention-named index
    # (…_on_enabled_and_cadence → …_on_notify_in_app_and_cadence).
    rename_column :notification_rules, :enabled, :notify_in_app
  end
end
