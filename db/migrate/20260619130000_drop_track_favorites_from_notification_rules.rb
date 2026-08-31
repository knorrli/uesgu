class DropTrackFavoritesFromNotificationRules < ActiveRecord::Migration[8.0]
  def change
    remove_column :notification_rules, :track_favorites, :boolean, default: false, null: false
  end
end
