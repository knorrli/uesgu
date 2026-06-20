require "application_system_test_case"

# Editing a saved filter: a plain form (explicit Save, no autosave) whose What/Where
# pickers are the SAME genre/location tree the events filter uses, shown as inline
# dropdown panels at desktop width. Picking stages into the form; Save commits and
# returns to the list. Selectors/option values are used instead of translated labels
# so the test ignores the locale.
class NotificationRuleEditTest < ApplicationSystemTestCase
  def setup
    @user = user
    # A root (no events) with one in-use child, so the genre tree renders it.
    @root = genre(name: "Zylorock", events_count: 0)
    @genre = genre(name: "Zylopunk", events_count: 1)
    @genre.set_parent!(@root)
    @rule = @user.notification_rules.new(name: "My alert", cadence: "weekly", weekday: 5, time_of_day: 1050)
    @rule.filter_attributes = { g: [@genre.name] } # no window → "added"
    @rule.save!
    event(start_date: Date.current + 3, genre_list: [@genre.name])
    sign_in_as @user
  end

  test "the editor shows the saved genre checked, the derived name, and a window select" do
    visit edit_notification_rule_path(@rule)

    assert_selector "h1", text: /Zylopunk/                 # name derived from the filter
    assert_selector "select[name='d[]']"                   # window select present
    saved = find("input[name='g[]'][value='#{@genre.name}']", visible: :all)
    assert saved.checked?, "the saved genre is pre-checked in the What tree"
  end

  test "picking another genre in the What panel and saving persists it" do
    visit edit_notification_rule_path(@rule)

    # Open the What panel (inline dropdown at desktop width) and pick the root.
    find(".filter-trigger[data-filter-sheets-field-param='what']").click
    find(".sheet[data-field=what] .opt--canton", text: @root.name).click
    find(".sheet[data-field=what] .sheet__apply").click

    # Explicit Save → back to the list, with both genres persisted.
    find(".rule-form input[type=submit]").click
    assert_current_path notification_rules_path
    assert_includes @rule.reload.genres, @root.name
    assert_includes @rule.genres, @genre.name
  end

  test "the What free-text row stages a typed query, persisted on Save" do
    visit edit_notification_rule_path(@rule)

    find(".filter-trigger[data-filter-sheets-field-param='what']").click
    field = find(".sheet[data-field=what] .sheet__search-input")
    field.send_keys("Radiohead")
    field.send_keys(:enter) # commitTyped → stages a q[] row (no submit in the editor)
    find(".sheet[data-field=what] .sheet__apply").click

    find(".rule-form input[type=submit]").click
    assert_current_path notification_rules_path
    assert_includes @rule.reload.queries, "Radiohead"
  end

  test "an off-quarter time snaps to the nearest quarter on change (no validation block)" do
    visit edit_notification_rule_path(@rule)

    time = find("input[type=time]")
    page.execute_script(<<~JS)
      const t = document.querySelector("input[type=time]")
      t.value = "18:04"
      t.dispatchEvent(new Event("change", { bubbles: true }))
    JS
    assert_equal "18:00", time.value
  end

  test "selecting a window hides the cadence picker (the rule becomes happening)" do
    visit edit_notification_rule_path(@rule)

    # added rule → cadence picker visible to start
    assert_selector "[data-rule-form-target='cadenceField']"
    # pick a window by value (locale-independent); the schedule reacts client-side
    find("select[name='d[]'] option[value='this_weekend']").select_option
    assert_no_selector "[data-rule-form-target='cadenceField']", visible: true

    # …and Save persists the flip to happening.
    find(".rule-form input[type=submit]").click
    assert_current_path notification_rules_path
    assert @rule.reload.happening?
    assert_equal ["this_weekend"], @rule.date_ranges
  end

  test "the email channel is disabled without an address" do
    visit edit_notification_rule_path(@rule)
    assert_selector "input[name='notification_rule[notify_email]'][disabled]", visible: :all
  end

  test "in-app is the master: unchecking it disables and clears push" do
    visit edit_notification_rule_path(@rule)
    push = find("input[type=checkbox][name='notification_rule[notify_push]']", visible: :all)
    refute push.disabled?, "push starts enabled while in-app is on"

    # Untick in-app → push is forced off and disabled client-side.
    find("input[type=checkbox][name='notification_rule[notify_in_app]']", visible: :all).click
    assert push.disabled?, "push disables when in-app goes off"
    refute push.checked?, "push is unchecked when in-app goes off"
  end
end
