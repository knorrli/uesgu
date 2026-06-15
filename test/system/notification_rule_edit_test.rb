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

  test "the title preview is the derived name and updates live as the filter changes" do
    event(start_date: Date.current + 4, style_list: ["Jazz"])
    visit notification_rules_path
    find(".rule-card__actions a[href='#{edit_notification_rule_path(@rule)}']").click

    preview = find("[data-rule-name-target='preview']")
    assert_match "Rock", preview.text            # derived from the saved filter

    # Add a style → the preview rebuilds live (no save needed).
    all("input[role='combobox']").first.send_keys("Jazz")
    find("[role=option]", text: "Jazz", match: :first).click
    assert_match "Jazz", preview.text

    # Pick a window → it joins the preview too.
    find("select[name='d[]'] option[value='this_weekend']").select_option
    assert_match(/·/, preview.text)

    find("input[type=submit]").click
    assert_current_path notification_rules_path
    assert_includes @rule.reload.style_list, "Jazz"
  end

  test "the inline filter shows the saved selection and a window select" do
    visit edit_notification_rule_path(@rule)

    assert_selector "select[name='d[]']"                 # window select present
    assert_selector "input[name='s[]'][value='Rock']", visible: :all  # styles pre-filled
  end

  test "the what field takes a free-text query and a picked style; email is disabled without an address" do
    event(start_date: Date.current + 4, style_list: ["Jazz"])
    visit edit_notification_rule_path(@rule)

    what = all("input[role='combobox']").first
    what.send_keys("Radiohead")
    what.send_keys(:enter)
    assert_selector "[data-tag-chip] input[name='q[]'][value='Radiohead']", visible: :all

    what.send_keys("Jazz")
    find("[role=option]", text: "Jazz", match: :first).click
    assert_selector "[data-tag-chip] input[name='s[]'][value='Jazz']", visible: :all

    # No email address saved → the email channel is disabled.
    assert_selector "input[name='notification_rule[notify_email]'][disabled]", visible: :all

    find("input[type=submit]").click
    assert_current_path notification_rules_path
    @rule.reload
    assert_includes @rule.queries, "Radiohead"   # free text → query
    assert_includes @rule.style_list, "Jazz"     # pick → style
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
