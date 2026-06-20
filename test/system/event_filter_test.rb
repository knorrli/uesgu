require "application_system_test_case"

# The desktop events filter now uses the same tree-picker sheet UI as mobile,
# shown as inline dropdown panels at desktop width (≥600px). Here we drive it at
# the default desktop screen size: picking a genre applies a tree-EXPANDING g[]
# filter (an ancestor pick catches descendant-tagged events), and the What panel's
# free-text row still commits a q[] query. (The old combobox lives on only in the
# rule editor, which Phase 3 reworks — its behaviour is covered there.)
class EventFilterTest < ApplicationSystemTestCase
  test "picking a genre applies a tree-expanding g[] filter" do
    rock = genre(name: "Zylorock", events_count: 1)
    shoegaze = genre(name: "Zyloshoe", events_count: 1)
    shoegaze.set_parent!(rock)
    e = event(start_date: Date.current + 3, genre_list: [shoegaze.name])

    visit events_path
    open_sheet("what")

    # Pick the ROOT — its subtree expansion must catch the child-tagged event.
    find(".sheet[data-field=what] .opt--canton", text: rock.name).click
    assert_selector ".sheet[data-field=what] input[value='#{rock.name}']:checked", visible: :all
    find(".sheet[data-field=what] .sheet__apply").click

    assert_current_path(/g%5B%5D=#{Regexp.escape(rock.name)}/)
    assert_selector ".filter-sheets__summary .filter-chip", text: rock.name
    # The descendant-tagged event matched the ancestor filter.
    assert_text e.title
  end

  test "removing the genre chip clears the filter" do
    rock = genre(name: "Zylorock", events_count: 1)
    child = genre(name: "Zylokid", events_count: 1)
    child.set_parent!(rock)
    event(start_date: Date.current + 3, genre_list: [child.name])

    visit events_path("g[]": rock.name)
    # filter-sheets#connect un-collapses the group holding the checked genre — wait
    # for it so the chip's remove action is bound before we click (else, under
    # full-suite load, the click can land before Stimulus connects and do nothing).
    assert_selector ".sheet[data-field=what] .loc-group:not(.collapsed)", visible: :all
    find(".filter-sheets__summary .filter-chip", text: rock.name).click # filter-sheets#remove

    assert_no_current_path(/g%5B%5D=/)
  end

  test "tapping a genre on an event row filters by it (g[]) and lights it" do
    rock = genre(name: "Taprock", events_count: 1)
    shoegaze = genre(name: "Tapshoe", events_count: 1)
    shoegaze.set_parent!(rock)
    event(start_date: Date.current + 3, genre_list: [shoegaze.name]) # row shows Tapshoe

    visit events_path
    find(".event-genres .filter-link", text: shoegaze.name).click

    assert_current_path(/g%5B%5D=#{Regexp.escape(shoegaze.name)}/)
    assert_selector ".event-genres .filter-link.active", text: shoegaze.name
  end

  test "the What free-text row commits the typed text as a q[] query" do
    event(start_date: Date.current + 3, genre_list: ["Zylogenre"])

    visit events_path
    open_sheet("what")
    field = find(".sheet[data-field=what] .sheet__search-input")
    field.click # settle focus before typing (open() parks focus elsewhere)
    field.send_keys("zzqx")
    assert_selector ".sheet[data-field=what] .opt--newquery", text: /zzqx/
    field.send_keys(:enter)

    assert_current_path(/q%5B%5D=zzqx/)
    assert_selector ".filter-sheets__summary .filter-chip", text: "zzqx"
  end

  test "clicking Apply commits typed text not submitted with Enter or the row" do
    event(start_date: Date.current + 3, genre_list: ["Zylogenre"])

    visit events_path
    open_sheet("what")
    field = find(".sheet[data-field=what] .sheet__search-input")
    field.click # settle focus before typing (open() parks focus elsewhere)
    field.send_keys("wubz")
    assert_selector ".sheet[data-field=what] .opt--newquery", text: /wubz/
    # Apply (not Enter, not the "search for X" row) still keeps the typed text.
    find(".sheet[data-field=what] .sheet__apply").click

    assert_current_path(/q%5B%5D=wubz/)
    assert_selector ".filter-sheets__summary .filter-chip", text: "wubz"
  end

  test "a filter panel closes via its × and via click-outside (desktop)" do
    rock = genre(name: "Closerock", events_count: 1)
    genre(name: "Closekid", events_count: 1).set_parent!(rock)
    event(start_date: Date.current + 3, genre_list: ["Closekid"])
    visit events_path

    # The × close button is shown on desktop too (not just mobile).
    open_sheet("what")
    find(".sheet[data-field=what] .sheet__close").click
    assert_no_selector ".sheet[data-field=what].sheet--open"

    # Clicking outside the open panel dismisses it.
    open_sheet("what")
    find(".events-toolbar").click
    assert_no_selector ".sheet[data-field=what].sheet--open"
  end

  private

  # The filter-sheets controller eager-loads asynchronously, so the first trigger
  # tap can land before it connects (a no-op). Retry until the panel opens — but the
  # trigger now TOGGLES, so check open-state before each click so we never toggle an
  # already-open panel shut. Capybara's has_selector wait polls; no fixed sleeps.
  def open_sheet(field)
    selector = ".sheet[data-field=#{field}].sheet--open"
    trigger = find(".filter-sheets .filter-trigger[data-filter-sheets-field-param=#{field}]")
    10.times do
      break if has_selector?(selector, wait: 0.3)
      trigger.click
    end
    assert_selector selector
  end
end
