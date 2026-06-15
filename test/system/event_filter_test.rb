require "application_system_test_case"

# The desktop free-text affordance (tag-picker + lib/search_for): a "search for
# «X»" row appears in the What dropdown when the typed text matches no style, and
# clicking it commits a free-text query. Mirrors the mobile sheet.
class EventFilterTest < ApplicationSystemTestCase
  # The shared tag-picker collector drives the desktop filter with auto-submit:
  # every pick/removal re-runs the filter and the chips come back server-rendered.
  test "picking a style auto-submits, and removing the chip auto-submits" do
    event(start_date: Date.current + 3, style_list: ["Rock"])

    visit events_path
    within ".filter-desktop" do
      find('input[role="combobox"]', match: :first).send_keys("Rock")
    end
    find("[role=option]", text: "Rock", match: :first).click

    assert_current_path(/s%5B%5D=Rock/)
    assert_selector ".filter-desktop .chips .tag", text: "Rock"

    find(".filter-desktop .chips .tag", text: "Rock").find(".tag__remove").click
    assert_no_selector ".filter-desktop .chips .tag", text: "Rock"
    assert_no_current_path(/s%5B%5D=Rock/)
  end

  test "desktop What field reveals a free-text row and commits it as a query" do
    event(start_date: Date.current + 3, style_list: ["Rock"])

    visit events_path

    # Wait for tag-picker#connect to have moved the (hidden) search-for row into the
    # listbox before typing — otherwise the first keystrokes can race the
    # controller connecting and the input listener misses them.
    assert_selector ".filter-desktop .filter-searchfor", visible: :all

    within ".filter-desktop" do
      # Per-char typing (real key events) so the combobox + our input listener
      # behave as for a user; .set() writes the value in one shot and fights the
      # combobox's autocomplete.
      find('input[role="combobox"]', match: :first).send_keys("zzqx")
    end

    # Row revealed by the input listener (auto-waited).
    assert_selector ".filter-searchfor", text: "zzqx"

    find(".filter-searchfor").click

    # The free-text query is now an applied chip (page reloaded with q[]).
    assert_selector ".filter-desktop .chips .tag", text: "zzqx"
  end

  test "an exact style match does not offer the free-text row" do
    event(start_date: Date.current + 3, style_list: ["Rock"])

    visit events_path
    assert_selector ".filter-desktop .filter-searchfor", visible: :all # controller connected
    within ".filter-desktop" do
      find('input[role="combobox"]', match: :first).send_keys("Rock")
    end

    assert_no_selector ".filter-searchfor:not([hidden])"
  end
end
