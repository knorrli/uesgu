require "application_system_test_case"

# Editing a saved filter: a plain form (explicit Save, no autosave) whose What/Where
# pickers are the SAME genre/location tree the events filter uses, shown as inline
# dropdown panels at desktop width. Picking stages into the form; Save commits and
# returns to the list. Selectors/option values are used instead of translated labels
# so the test ignores the locale.
class SavedFilterEditTest < ApplicationSystemTestCase
  def setup
    @user = user
    # A root (no events) with one in-use child, so the genre tree renders it.
    @root = genre(name: "Zylorock", events_count: 0)
    @genre = genre(name: "Zylopunk", events_count: 1)
    @genre.set_parent!(@root)
    @rule = @user.saved_filters.new(name: "My alert", cadence: "weekly", weekday: 5, time_of_day: 1050)
    @rule.filter_attributes = { g: [@genre.name] } # no window → "added"
    @rule.save!
    event(start_date: Date.current + 3, genre_list: [@genre.name])
    sign_in_as @user
  end

  test "the editor shows the saved genre checked, the derived name, and a window trigger" do
    visit edit_saved_filter_path(@rule)

    assert_selector "h1", text: /Zylopunk/                                   # name derived from the filter
    assert_selector ".filter-trigger[data-filter-sheets-field-param='when']" # window trigger present (panel, not a select)
    assert_selector ".sheet[data-field=when] input[name='d[]']", visible: :all, minimum: 1
    saved = find("input[name='g[]'][value='#{@genre.name}']", visible: :all)
    assert saved.checked?, "the saved genre is pre-checked in the What tree"
  end

  test "the title updates live as the filter changes (before any save)" do
    visit edit_saved_filter_path(@rule)
    assert_selector "h1", text: /Zylopunk/

    # Pick the root genre in the What panel — the h1 reflects it immediately, with
    # no round-trip (the form hasn't been submitted).
    find(".filter-trigger[data-filter-sheets-field-param='what']").click
    find(".sheet[data-field=what] .opt--canton", text: @root.name).click
    assert_selector "h1", text: /#{@root.name}/
    assert_selector "h1", text: /Zylopunk/ # the original pick is still named too
  end

  test "picking another genre in the What panel and saving persists it" do
    visit edit_saved_filter_path(@rule)

    # Open the What panel (inline dropdown at desktop width) and pick the root.
    find(".filter-trigger[data-filter-sheets-field-param='what']").click
    find(".sheet[data-field=what] .opt--canton", text: @root.name).click
    find(".sheet[data-field=what] .sheet__apply").click

    # Explicit Save → back to the list, with both genres persisted.
    find(".saved-filter-form input[type=submit]").click
    assert_current_path saved_filters_path
    assert_includes @rule.reload.genres, @root.name
    assert_includes @rule.genres, @genre.name
  end

  test "the What free-text row stages a typed query, persisted on Save" do
    visit edit_saved_filter_path(@rule)

    find(".filter-trigger[data-filter-sheets-field-param='what']").click
    field = find(".sheet[data-field=what] .sheet__search-input")
    field.send_keys("Radiohead")
    field.send_keys(:enter) # commitTyped → stages a q[] row (no submit in the editor)
    find(".sheet[data-field=what] .sheet__apply").click

    find(".saved-filter-form input[type=submit]").click
    assert_current_path saved_filters_path
    assert_includes @rule.reload.queries, "Radiohead"
  end

  test "the time picker only offers quarter-hour minutes (off-quarter is impossible)" do
    visit edit_saved_filter_path(@rule)

    # The native time input was replaced by hour + minute selects; the minute select
    # offers only the quarter values the scheduler honours, so nothing to snap.
    minutes = find("select[name='saved_filter[time_minute]']")
    assert_equal %w[00 15 30 45], minutes.all("option").map(&:value)
    assert_equal "30", minutes.value # @rule is 17:30 (time_of_day 1050)
  end

  test "selecting a window hides the cadence picker (the rule becomes happening)" do
    visit edit_saved_filter_path(@rule)

    # added rule → cadence picker visible to start
    assert_selector "[data-saved-filter-form-target='cadenceField']"
    # Open the When panel and pick a window by value (locale-independent). The
    # native box is visually hidden (.opt), so click its label; the schedule reacts
    # client-side as the change bubbles to the form.
    find(".filter-trigger[data-filter-sheets-field-param='when']").click
    find(".sheet[data-field=when] input[name='d[]'][value='this_weekend']", visible: :all).ancestor("label").click
    assert_no_selector "[data-saved-filter-form-target='cadenceField']", visible: true

    # …and Save persists the flip to happening.
    find(".sheet[data-field=when] .sheet__apply").click
    find(".saved-filter-form input[type=submit]").click
    assert_current_path saved_filters_path
    assert @rule.reload.happening?
    assert_equal ["this_weekend"], @rule.date_ranges
  end

  test "the email channel is disabled without an address" do
    visit edit_saved_filter_path(@rule)
    assert_selector "input[name='saved_filter[notify_email]'][disabled]", visible: :all
  end

  test "in-app is the master: unchecking it disables and clears push" do
    # Push is only enabled when it's actually set up (VAPID keys + a registered
    # device); otherwise it's disabled for that reason regardless of the master.
    # Make it ready so we isolate the in-app-master cascade.
    ENV["VAPID_PUBLIC_KEY"] = "test-public-key"
    ENV["VAPID_PRIVATE_KEY"] = "test-private-key"
    @user.push_subscriptions.create!(endpoint: "https://push.example/abc",
                                     p256dh_key: "p256", auth_key: "auth")

    visit edit_saved_filter_path(@rule)
    push = find("input[type=checkbox][name='saved_filter[notify_push]']", visible: :all)
    refute push.disabled?, "push starts enabled while in-app is on"

    # Untick in-app → push is forced off and disabled client-side.
    find("input[type=checkbox][name='saved_filter[notify_in_app]']", visible: :all).click
    assert push.disabled?, "push disables when in-app goes off"
    refute push.checked?, "push is unchecked when in-app goes off"
  ensure
    ENV.delete("VAPID_PUBLIC_KEY")
    ENV.delete("VAPID_PRIVATE_KEY")
  end

  test "unticking 'highlight in feed' persists (default is on)" do
    visit edit_saved_filter_path(@rule)

    box = find("input[type=checkbox][name='saved_filter[highlight_in_feed]']", visible: :all)
    assert box.checked?, "highlight starts on (the DB default)"

    box.click
    find(".saved-filter-form input[type=submit]").click
    assert_current_path saved_filters_path
    assert_not @rule.reload.highlight_in_feed?, "the unticked toggle is persisted"
  end
end
