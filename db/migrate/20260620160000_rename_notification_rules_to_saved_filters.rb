# The model is a saved landing-page filter (notification delivery optional), so
# NotificationRule → SavedFilter. Rename the table and the notifications FK to
# match. rename_table/rename_column also rename the convention-named indexes.
class RenameNotificationRulesToSavedFilters < ActiveRecord::Migration[8.0]
  def change
    rename_table :notification_rules, :saved_filters
    rename_column :notifications, :notification_rule_id, :saved_filter_id
  end
end
