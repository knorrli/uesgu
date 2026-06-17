require "application_system_test_case"

# The events toolbar (interests shortcut + notify + view switcher). On mobile the
# two action labels collapse to icon-only so the row stays on one line; the labels
# return on desktop. Pure CSS (a media query on .toolbar-action__label), verified
# here at both widths.
class EventsToolbarTest < ApplicationSystemTestCase
  test "interests/notify labels are icon-only on mobile and text on desktop" do
    event(start_date: Date.current + 3, style_list: ["Rock"])
    u = sign_in_as user
    u.update!(style_list: ["Rock"]) # follow a style → the interests shortcut shows

    visit events_path(s: ["Rock"]) # an active filter → the notify action shows

    # Both actions render with their icons regardless of width.
    assert_selector ".favorites-filter-link .fav-star"
    assert_selector ".notify-filter-link .ph-bell"

    # Desktop (default 1300px window): the labels are shown.
    assert_selector ".favorites-filter-link .toolbar-action__label", visible: true
    assert_selector ".notify-filter-link .toolbar-action__label", visible: true

    # Mobile: labels collapse to icon-only (the icons stay).
    page.current_window.resize_to(390, 800)
    assert_no_selector ".toolbar-action__label", visible: true
    assert_selector ".favorites-filter-link .fav-star"
    assert_selector ".notify-filter-link .ph-bell"
  end
end
