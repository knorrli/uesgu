require "application_system_test_case"

class SavedFiltersMenuTest < ApplicationSystemTestCase
  test "the saved-filters menu shows by the chips at all widths when a filter is active" do
    event(start_date: Date.current + 3, genre_list: ["Rock"])
    sign_in_as user

    visit events_path("g[]": ["Rock"])

    assert_selector ".filter-menu__toggle .ph-funnel", visible: true
    find(".filter-menu__toggle").click
    assert_selector ".filter-menu__save .save-filter-plus", visible: true

    page.current_window.resize_to(390, 800)
    assert_selector ".filter-menu__toggle .ph-funnel", visible: true
  end

  test "the saved state is a solid funnel (no + badge)" do
    event(start_date: Date.current + 3, genre_list: ["Rock"])
    u = sign_in_as user
    r = u.saved_filters.new(cadence: "daily", time_of_day: 540)
    r.filter_attributes = { g: ["Rock"] }
    r.save!

    visit events_path("g[]": ["Rock"])
    assert_selector ".filter-menu__toggle .funnel-fill", visible: true
    assert_no_selector ".save-filter-plus"
  end

  test "on an empty feed the menu offers the notify-on-everything save" do
    event(start_date: Date.current + 3)
    sign_in_as user

    visit events_path

    assert_selector ".filter-menu__toggle .ph-funnel", visible: true
    find(".filter-menu__toggle").click
    assert_selector ".filter-menu__save .save-filter-plus", visible: true
  end
end
