class RenameNotificationRulesToSavedFilters < ActiveRecord::Migration[8.0]
  def change
    rename_table :notification_rules, :saved_filters
    rename_column :notifications, :notification_rule_id, :saved_filter_id
  end
end
