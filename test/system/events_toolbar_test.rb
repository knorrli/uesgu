require "application_system_test_case"

# The events toolbar (the list/calendar view switcher) and the chip-row
# saved-filters menu — a funnel <details> dropdown that SAVES the current filter and
# APPLIES a saved one. The toggle sits by the applied-filter chips for any signed-in
# user (an empty filter saves as the all-events rule); its items live in the dropdown
# panel. Desktop + phone.
class EventsToolbarTest < ApplicationSystemTestCase
  test "the saved-filters menu shows by the chips at all widths when a filter is active" do
    event(start_date: Date.current + 3, genre_list: ["Rock"])
    sign_in_as user

    visit events_path("g[]": ["Rock"]) # an active filter → the menu toggle shows

    # Desktop (default 1300px window): the funnel toggle is visible; opening it
    # reveals the "save this filter" item with its + add badge.
    assert_selector ".filter-menu__toggle .ph-funnel", visible: true
    find(".filter-menu__toggle").click
    assert_selector ".filter-menu__save .save-filter-plus", visible: true

    # Mobile: the toggle is still present by the chips.
    page.current_window.resize_to(390, 800)
    assert_selector ".filter-menu__toggle .ph-funnel", visible: true
  end

  test "the saved state is a solid funnel (no + badge)" do
    event(start_date: Date.current + 3, genre_list: ["Rock"])
    u = sign_in_as user
    r = u.saved_filters.new(cadence: "daily", time_of_day: 540)
    r.filter_attributes = { g: ["Rock"] }
    r.save!

    visit events_path("g[]": ["Rock"]) # this exact filter is saved → lit, solid funnel
    assert_selector ".filter-menu__toggle .funnel-fill", visible: true
    assert_no_selector ".save-filter-plus"
  end

  test "on an empty feed the menu offers the notify-on-everything save" do
    event(start_date: Date.current + 3)
    sign_in_as user

    visit events_path # no filter, no saved filters

    # The funnel toggle still shows: opening it reveals the save item (the + badge)
    # which saves the empty filter as the all-events rule.
    assert_selector ".filter-menu__toggle .ph-funnel", visible: true
    find(".filter-menu__toggle").click
    assert_selector ".filter-menu__save .save-filter-plus", visible: true
  end
end
