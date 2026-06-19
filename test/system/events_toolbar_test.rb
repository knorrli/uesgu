require "application_system_test_case"

# The events toolbar (interests shortcut + view switcher) and the ★ save control.
# The interests label shows at every width — the save/notify cluster sits down by
# the applied-filter chips (not in the toolbar), so the left cluster has room. The
# ★ is icon-only and only appears when a filter is active. Verified desktop + phone.
class EventsToolbarTest < ApplicationSystemTestCase
  test "interests keeps its label at all widths; the save star shows by the chips when a filter is active" do
    event(start_date: Date.current + 3, genre_list: ["Rock"])
    u = sign_in_as user
    u.update!(style_list: ["Rock"]) # follow a style → the interests shortcut shows

    visit events_path("g[]": ["Rock"]) # an active filter → the save star shows

    # Desktop (default 1300px window): interests label shown, ★ visible.
    assert_selector ".favorites-filter-link .toolbar-action__label", visible: true
    assert_selector ".save-filter-link .ph-star", visible: true

    # Mobile: the interests label stays (no longer collapses), and the ★ is still
    # present by the chips.
    page.current_window.resize_to(390, 800)
    assert_selector ".favorites-filter-link .toolbar-action__label", visible: true
    assert_selector ".save-filter-link .ph-star", visible: true
  end

  test "no save star when the filter is empty" do
    event(start_date: Date.current + 3)
    sign_in_as user

    visit events_path # no filter

    assert_no_selector ".save-filter-link"
  end
end
