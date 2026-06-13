# Reframe: a notification rule is now "a saved landing-page filter + a schedule",
# not a bespoke builder. The filter params (queries/style_list/location_list/
# date_ranges) live in the existing `filter` jsonb; added-vs-happening is inferred
# from whether a relative date window is present, so the explicit content_type /
# window / scope columns go away. track_favorites keeps a favorites alert live
# (re-resolved at send time) instead of freezing the tags.
class ReframeNotificationRulesAroundFilter < ActiveRecord::Migration[8.0]
  def change
    add_column :notification_rules, :track_favorites, :boolean, null: false, default: false

    remove_column :notification_rules, :content_type, :string
    remove_column :notification_rules, :window, :string
    remove_column :notification_rules, :scope, :string
  end
end
