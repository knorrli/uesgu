require "application_system_test_case"

# Editing an alert (Point 2, inline): the whole rule — schedule, channels, name,
# and the filter (multiselect comboboxes + a window select) — is edited on one
# form, no events-page round-trip. Selectors/option-values are used instead of
# translated labels so the test doesn't care which locale renders.
class NotificationRuleEditTest < ApplicationSystemTestCase
  def setup
    @user = user
    @rule = @user.notification_rules.new(name: "My alert", cadence: "weekly", weekday: 5, time_of_day: 1050)
    @rule.filter_attributes = { s: ["Rock"] } # no window → "added"
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

  test "the inline filter shows the saved selection and a window select" do
    visit edit_notification_rule_path(@rule)

    assert_selector "select[name='d[]']"                 # window select present
    assert_selector "input[name='s[]'][value='Rock']", visible: :all  # styles pre-filled
  end

  test "selecting a window flips the rule to happening and hides the cadence picker" do
    visit edit_notification_rule_path(@rule)

    # added rule → cadence picker visible to start
    assert_selector "[data-rule-form-target='cadenceField']"
    # pick a window by value (locale-independent); the schedule reacts
    find("select[name='d[]'] option[value='this_weekend']").select_option
    assert_no_selector "[data-rule-form-target='cadenceField']", visible: true

    find("input[type=submit]").click
    assert_current_path notification_rules_path

    @rule.reload
    assert @rule.happening?
    assert_equal ["this_weekend"], @rule.date_ranges
  end
end
