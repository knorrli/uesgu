require "application_system_test_case"

# The desktop free-text affordance (tag-picker + lib/search_for): a "search for
# «X»" row is ALWAYS present in the open What dropdown — a "type to search" hint
# when blank, the typed query once you start — and clicking it commits a
# free-text query. Mirrors the mobile sheet.
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

  test "the free-text row is always offered, even for an exact style match" do
    event(start_date: Date.current + 3, style_list: ["Rock"])

    visit events_path
    assert_selector ".filter-desktop .filter-searchfor", visible: :all # controller connected

    # Open the dropdown without typing: the blank hint shows and isn't committable.
    find(".filter-desktop input[role='combobox']", match: :first).click
    assert_selector ".filter-desktop .filter-searchfor", visible: true
    assert_equal "", find(".filter-desktop .filter-searchfor", visible: true)["data-value"]

    # Typing an exact style name still offers the row (free text is a distinct
    # action — it was previously suppressed on an exact match).
    within ".filter-desktop" do
      find('input[role="combobox"]', match: :first).send_keys("Rock")
    end
    assert_selector ".filter-desktop .filter-searchfor", text: "Rock"
  end

  # Enter in the What field commits what you TYPED as a free-text query — even
  # when it's a prefix of a style ("Bl" → Blues) — rather than the gem hijacking
  # it to that style. (autocomplete: :list + tag-picker#commitOnEnter.) Clicking
  # the input first locks focus so Enter lands on it, not the body.
  test "Enter on a prefix of a style commits the typed text as free text" do
    event(start_date: Date.current + 3, style_list: ["Blues"])

    visit events_path
    what = find(".filter-desktop input[role='combobox']", match: :first)
    what.click
    what.send_keys("Bl", :enter)

    assert_selector ".filter-desktop .chips input[name='q[]'][value='Bl']", visible: :all
    assert_no_selector ".filter-desktop .chips input[name='s[]']", visible: :all
  end

  test "Enter selects the style when the text names it exactly, or you arrow to it" do
    event(start_date: Date.current + 3, style_list: ["Blues"])

    # Exact name → the style.
    visit events_path
    exact = find(".filter-desktop input[role='combobox']", match: :first)
    exact.click
    exact.send_keys("Blues", :enter)
    assert_selector ".filter-desktop .chips input[name='s[]'][value='Blues']", visible: :all

    # Arrow down to the option, then Enter → the style (not free text).
    visit events_path
    arrowed = find(".filter-desktop input[role='combobox']", match: :first)
    arrowed.click
    arrowed.send_keys("Bl", :down, :enter)
    assert_selector ".filter-desktop .chips input[name='s[]'][value='Blues']", visible: :all
  end
end
