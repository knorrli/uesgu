require "application_system_test_case"

# The events toolbar (just the list/calendar view switcher now) and the save-filter
# control. It's an icon-only funnel (outline + "+" when not saved) that sits by the
# applied-filter chips, only when a filter is active. Verified at desktop and phone.
class EventsToolbarTest < ApplicationSystemTestCase
  test "the save funnel shows by the chips at all widths when a filter is active" do
    event(start_date: Date.current + 3, genre_list: ["Rock"])
    sign_in_as user

    visit events_path("g[]": ["Rock"]) # an active filter → the save funnel shows

    # Desktop (default 1300px window): outline funnel + the "+" add badge.
    assert_selector ".save-filter-link .ph-funnel", visible: true
    assert_selector ".save-filter-link .save-filter-plus", visible: true

    # Mobile: still present by the chips.
    page.current_window.resize_to(390, 800)
    assert_selector ".save-filter-link .ph-funnel", visible: true
  end

  test "the saved state is a solid funnel (no + badge)" do
    event(start_date: Date.current + 3, genre_list: ["Rock"])
    u = sign_in_as user
    r = u.saved_filters.new(cadence: "daily", time_of_day: 540)
    r.filter_attributes = { g: ["Rock"] }
    r.save!

    visit events_path("g[]": ["Rock"]) # this exact filter is saved → lit, solid funnel
    assert_selector ".save-filter-link.active .funnel-fill", visible: true
    assert_no_selector ".save-filter-plus"
  end

  test "no save funnel when the filter is empty" do
    event(start_date: Date.current + 3)
    sign_in_as user

    visit events_path # no filter

    assert_no_selector ".save-filter-link"
  end
end
