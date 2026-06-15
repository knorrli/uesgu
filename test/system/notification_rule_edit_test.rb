require "application_system_test_case"

# Editing an alert (submit-on-select, autosave): the whole rule — schedule,
# channels, name, and the filter (multiselect comboboxes + a window select) — is
# edited on one form with NO Save button. Every change submits and the form
# re-renders in its turbo frame with the canonical server state. Selectors/option
# values are used instead of translated labels so the test ignores the locale.
class NotificationRuleEditTest < ApplicationSystemTestCase
  def setup
    @user = user
    @rule = @user.notification_rules.new(name: "My alert", cadence: "weekly", weekday: 5, time_of_day: 1050)
    @rule.filter_attributes = { s: ["Rock"] } # no window → "added"
    @rule.save!
    event(start_date: Date.current + 3, style_list: ["Rock"])
    sign_in_as @user
  end

  test "the title is the derived name and autosaving the filter updates it" do
    event(start_date: Date.current + 4, style_list: ["Jazz"])
    visit edit_notification_rule_path(@rule)

    assert_selector "h1", text: "Rock"   # derived from the saved filter

    # Add a style → autosaves → the server re-renders the title (no Save button).
    all("input[role='combobox']").first.send_keys("Jazz")
    find("[role=option]", text: "Jazz", match: :first).click
    assert_selector "h1", text: /Jazz/                 # server-rendered after autosave
    assert_includes @rule.reload.style_list, "Jazz"    # persisted without a Save click

    # Pick a window → autosaves → it shows as a green (calendar) tag in the row.
    find("select[name='d[]'] option[value='this_weekend']").select_option
    assert_selector ".chips [data-tag-chip] .ph-calendar-dots" # server-rendered after autosave
    assert_equal ["this_weekend"], @rule.reload.date_ranges
  end

  test "an off-quarter time snaps to the nearest quarter on change (no validation block)" do
    visit edit_notification_rule_path(@rule)

    time = find("input[type=time]")
    # No step= constraint, so an off-quarter value is accepted, then snapped
    # (synchronously, before autosave fires).
    page.execute_script(<<~JS)
      const t = document.querySelector("input[type=time]")
      t.value = "18:04"
      t.dispatchEvent(new Event("change", { bubbles: true }))
    JS
    assert_equal "18:00", time.value
    # (autosave persistence of the schedule is covered by the integration test)
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
    assert_selector "h1", text: /Radiohead/      # autosaved free-text query → derived name
    assert_includes @rule.reload.queries, "Radiohead"

    all("input[role='combobox']").first.send_keys("Jazz")
    find("[role=option]", text: "Jazz", match: :first).click
    assert_selector "h1", text: /Jazz/
    assert_includes @rule.reload.style_list, "Jazz"

    # No email address saved → the email channel is disabled.
    assert_selector "input[name='notification_rule[notify_email]'][disabled]", visible: :all
  end

  test "selecting a window flips the rule to happening and hides the cadence picker" do
    visit edit_notification_rule_path(@rule)

    # added rule → cadence picker visible to start
    assert_selector "[data-rule-form-target='cadenceField']"
    # pick a window by value (locale-independent); the schedule reacts and autosaves
    find("select[name='d[]'] option[value='this_weekend']").select_option
    assert_no_selector "[data-rule-form-target='cadenceField']", visible: true
    assert_selector ".chips [data-tag-chip] .ph-calendar-dots" # autosaved (window tag rendered)

    assert @rule.reload.happening?
    assert_equal ["this_weekend"], @rule.date_ranges
  end
end
