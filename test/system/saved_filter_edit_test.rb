require "application_system_test_case"

class SavedFilterEditTest < ApplicationSystemTestCase
  def setup
    @user = user
    @root = genre(name: "Zylorock", events_count: 0)
    @genre = genre(name: "Zylopunk", events_count: 1)
    @genre.set_parent!(@root)
    @rule = @user.saved_filters.new(name: "My alert", cadence: "weekly", weekday: 5, time_of_day: 1050)
    @rule.filter_attributes = { g: [@genre.name] }
    @rule.save!
    event(start_date: Date.current + 3, genre_list: [@genre.name])
    sign_in_as @user
  end

  test "the editor shows the saved genre checked, the derived name, and a window trigger" do
    visit edit_saved_filter_path(@rule)

    assert_selector "h1", text: /Zylopunk/
    assert_selector ".filter-trigger[data-filter-sheets-field-param='when']"
    assert_selector ".sheet[data-field=when] input[name='d[]']", visible: :all, minimum: 1
    saved = find("input[name='g[]'][value='#{@genre.name}']", visible: :all)
    assert saved.checked?, "the saved genre is pre-checked in the What tree"
  end

  test "the title updates live as the filter changes (before any save)" do
    visit edit_saved_filter_path(@rule)
    assert_selector "h1", text: /Zylopunk/

    find(".filter-trigger[data-filter-sheets-field-param='what']").click
    find(".sheet[data-field=what] .opt--top", text: @root.name).click
    assert_selector "h1", text: /#{@root.name}/
    assert_selector "h1", text: /Zylopunk/
  end

  test "picking another genre in the What panel and saving persists it" do
    visit edit_saved_filter_path(@rule)

    find(".filter-trigger[data-filter-sheets-field-param='what']").click
    find(".sheet[data-field=what] .opt--top", text: @root.name).click
    find(".sheet[data-field=what] .sheet__apply").click

    find(".saved-filter-form input[type=submit]").click
    assert_current_path saved_filters_path
    assert_includes @rule.reload.genres, @root.name
    assert_includes @rule.genres, @genre.name
  end

  test "Abbrechen leaves the editor without saving applied edits" do
    visit edit_saved_filter_path(@rule)

    find(".filter-trigger[data-filter-sheets-field-param='what']").click
    find(".sheet[data-field=what] .opt--top", text: @root.name).click
    find(".sheet[data-field=what] .sheet__apply").click
    find(".form-actions > a.button-small:not(.danger)").click

    assert_current_path saved_filters_path
    refute_includes @rule.reload.genres, @root.name
  end

  test "the What free-text row stages a typed query, persisted on Save" do
    visit edit_saved_filter_path(@rule)

    find(".filter-trigger[data-filter-sheets-field-param='what']").click
    field = find(".sheet[data-field=what] .sheet__search-input")
    field.send_keys("Radiohead")
    field.send_keys(:enter)
    find(".sheet[data-field=what] .sheet__apply").click

    find(".saved-filter-form input[type=submit]").click
    assert_current_path saved_filters_path
    assert_includes @rule.reload.queries, "Radiohead"
  end

  test "the time picker only offers quarter-hour minutes (off-quarter is impossible)" do
    visit edit_saved_filter_path(@rule)

    minutes = find("select[name='saved_filter[time_minute]']")
    assert_equal %w[00 15 30 45], minutes.all("option").map(&:value)
    assert_equal "30", minutes.value
  end

  test "selecting a window hides the cadence picker (the rule becomes happening)" do
    visit edit_saved_filter_path(@rule)

    assert_selector "[data-saved-filter-form-target='cadenceField']"
    find(".filter-trigger[data-filter-sheets-field-param='when']").click
    find(".sheet[data-field=when] input[name='d[]'][value='this_weekend']", visible: :all).ancestor("label").click
    assert_no_selector "[data-saved-filter-form-target='cadenceField']", visible: true

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
    ENV["VAPID_PUBLIC_KEY"] = "test-public-key"
    ENV["VAPID_PRIVATE_KEY"] = "test-private-key"
    @user.push_subscriptions.create!(endpoint: "https://push.example/abc",
                                     p256dh_key: "p256", auth_key: "auth")

    visit edit_saved_filter_path(@rule)
    push = find("input[type=checkbox][name='saved_filter[notify_push]']", visible: :all)
    refute push.disabled?, "push starts enabled while in-app is on"

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
