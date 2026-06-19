# track_favorites was the "keep this alert synced with my followed tags" flag, a
# favorites-feature concept. Favorites dissolve into saved filters (Phase 4), so
# the flag has no meaning anymore. No real users yet → just drop the column.
class DropTrackFavoritesFromNotificationRules < ActiveRecord::Migration[8.0]
  def change
    remove_column :notification_rules, :track_favorites, :boolean, default: false, null: false
  end
end
