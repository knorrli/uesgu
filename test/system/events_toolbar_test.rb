require "application_system_test_case"

# The events toolbar (interests shortcut + view switcher) and the "notify me about
# this filter" bell. The interests label now shows at every width — the bell moved
# out of the toolbar down to the chip row, so the left cluster has room for it. The
# bell is an icon-only control pinned to the right of the applied-filter chips, and
# only appears when a filter is active. Verified at desktop and phone widths.
class EventsToolbarTest < ApplicationSystemTestCase
  test "interests keeps its label at all widths; notify bell shows by the chips when a filter is active" do
    event(start_date: Date.current + 3, style_list: ["Rock"])
    u = sign_in_as user
    u.update!(style_list: ["Rock"]) # follow a style → the interests shortcut shows

    visit events_path(s: ["Rock"]) # an active filter → the notify bell shows

    # Desktop (default 1300px window): interests label shown, notify bell visible.
    assert_selector ".favorites-filter-link .toolbar-action__label", visible: true
    assert_selector ".notify-filter-link .ph-bell", visible: true

    # Mobile: the interests label stays (no longer collapses), and the bell is
    # still present by the chips (the mobile sheets' copy takes over).
    page.current_window.resize_to(390, 800)
    assert_selector ".favorites-filter-link .toolbar-action__label", visible: true
    assert_selector ".notify-filter-link .ph-bell", visible: true
  end

  test "no notify bell when the filter is empty" do
    event(start_date: Date.current + 3)
    sign_in_as user

    visit events_path # no filter

    assert_no_selector ".notify-filter-link"
  end
end
