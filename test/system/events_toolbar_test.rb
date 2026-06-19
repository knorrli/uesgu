require "application_system_test_case"

# The events toolbar (just the list/calendar view switcher now) and the ★ save
# control. The ★ is icon-only and sits by the applied-filter chips, only when a
# filter is active. Verified at desktop and phone widths.
class EventsToolbarTest < ApplicationSystemTestCase
  test "the save star shows by the chips at all widths when a filter is active" do
    event(start_date: Date.current + 3, genre_list: ["Rock"])
    sign_in_as user

    visit events_path("g[]": ["Rock"]) # an active filter → the save star shows

    # Desktop (default 1300px window).
    assert_selector ".save-filter-link .ph-star", visible: true

    # Mobile: still present by the chips.
    page.current_window.resize_to(390, 800)
    assert_selector ".save-filter-link .ph-star", visible: true
  end

  test "no save star when the filter is empty" do
    event(start_date: Date.current + 3)
    sign_in_as user

    visit events_path # no filter

    assert_no_selector ".save-filter-link"
  end
end
