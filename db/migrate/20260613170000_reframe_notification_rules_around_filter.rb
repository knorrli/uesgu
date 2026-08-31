class ReframeNotificationRulesAroundFilter < ActiveRecord::Migration[8.0]
  def change
    add_column :notification_rules, :track_favorites, :boolean, null: false, default: false

    remove_column :notification_rules, :content_type, :string
    remove_column :notification_rules, :window, :string
    remove_column :notification_rules, :scope, :string
  end
end
