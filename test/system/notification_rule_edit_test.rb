require "application_system_test_case"

# Editing an alert (Point 2): the edit form changes schedule/name in place, and
# "Filter ändern" round-trips through the events page to adjust the filter and
# save it back onto the same rule. Selectors/hrefs are used instead of
# translated labels so the test doesn't care which locale renders.
class NotificationRuleEditTest < ApplicationSystemTestCase
  def setup
    @user = user
    @rule = @user.notification_rules.new(name: "My alert", cadence: "weekly", weekday: 5, time_of_day: 1050)
    @rule.filter_attributes = { s: ["Rock"] }
    @rule.save!
    event(start_date: Date.current + 3, style_list: ["Rock"])
    sign_in_as @user
  end

  test "renaming a rule on the edit form persists" do
    visit notification_rules_path
    find(".rule-card__actions a[href='#{edit_notification_rule_path(@rule)}']").click

    assert_field "notification_rule[name]", with: "My alert"
    fill_in "notification_rule[name]", with: "Renamed alert"
    find("input[type=submit]").click

    assert_current_path notification_rules_path
    assert_text "Renamed alert"
  end

  test "Filter ändern round-trips through the events page and saves back to the rule" do
    visit edit_notification_rule_path(@rule)

    # The filter is shown read-only with a round-trip link to the events page.
    change_link = find("a[href*='rule_id=#{@rule.id}']")
    change_link.click

    # On the events page in edit mode, the notify row offers "save filter" back
    # to this rule (link points at the rule's update/edit path).
    save = find("a.notify-filter-link[href*='/notification_rules/#{@rule.id}/edit']")
    save.click

    # Back on the edit form; saving completes the round trip.
    assert_field "notification_rule[name]", with: "My alert"
    find("input[type=submit]").click
    assert_current_path notification_rules_path
  end
end
