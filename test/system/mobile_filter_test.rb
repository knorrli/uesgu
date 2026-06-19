require "application_system_test_case"

# The mobile filter sheets (<600px). Companion to event_filter_test.rb, which
# drives the same UI at desktop width; here we exercise the full-screen What sheet.
class MobileFilterTest < ApplicationSystemTestCase
  # The keyboard's Enter / "search" key on the What field commits what you TYPED as
  # a free-text query — no need to first tap the "search for «X»" row. Mirrors the
  # desktop combobox's commit-on-Enter (filter_sheets#commitTyped).
  test "Enter in the What sheet commits the typed text as a free-text query" do
    event(start_date: Date.current + 3, style_list: ["Rock"])

    page.current_window.resize_to(390, 800) # below the 600px sheet breakpoint
    visit events_path

    open_what_sheet
    field = find(".sheet[data-field=what] .sheet__search-input")
    field.click # settle focus on the field before typing (open() parks it on close)
    field.send_keys("zzqx")
    # The free-text row reflects the typed text — proves the input handler ran, so
    # the Enter below can't race the keystrokes (same guard as the desktop test).
    assert_selector ".sheet[data-field=what] .opt--newquery", text: /zzqx/
    field.send_keys(:enter)

    # Applied as a q[] free-text filter: the page reloaded and the summary chip is
    # server-rendered, so it proves the query round-tripped (not just client state).
    assert_current_path(/q%5B%5D=zzqx/)
    assert_selector ".filter-sheets__summary .filter-chip", text: "zzqx"
  end

  # The What sheet renders the curated GENRE TREE (roots → children), like the
  # Where sheet's canton tree. Picking a node commits a tree-expanding g[] filter:
  # an ancestor pick catches events tagged with any descendant. The search box
  # filters the tree.
  test "What sheet renders the genre tree and applies a genre pick as g[]" do
    rock = genre(name: "Zylorock", events_count: 1)
    shoegaze = genre(name: "Zyloshoe", events_count: 1)
    shoegaze.set_parent!(rock)
    e = event(start_date: Date.current + 3, genre_list: [shoegaze.name])

    page.current_window.resize_to(390, 800) # below the 600px sheet breakpoint
    visit events_path

    open_what_sheet
    # The root is a visible browse row; its expand chevron reveals the child.
    assert_selector ".sheet[data-field=what] .opt--canton", text: rock.name, visible: true

    # Pick the root — subtree expansion must catch the child-tagged event. Waiting
    # on :checked avoids racing the click.
    find(".sheet[data-field=what] .opt--canton", text: rock.name).click
    assert_selector ".sheet[data-field=what] input[value='#{rock.name}']:checked", visible: :all

    find(".sheet[data-field=what] .sheet__apply").click

    # Server-rendered chip proves the genre round-tripped as a g[] filter.
    assert_selector ".filter-sheets__summary .filter-chip", text: rock.name
    assert_current_path(/g%5B%5D=/)
    # The descendant-tagged event matched the ancestor filter.
    assert_text e.title
  end

  # The blank "type to search" hint at the top of the What sheet is a tap target:
  # people tap it expecting the search field to focus so they can type. It should,
  # rather than do nothing (filter_sheets#addQuery focuses the field when blank).
  test "tapping the blank type-to-search hint focuses the What search field" do
    event(start_date: Date.current + 3, style_list: ["Zynthwave"])

    page.current_window.resize_to(390, 800) # below the 600px sheet breakpoint
    visit events_path

    open_what_sheet
    field = ".sheet[data-field=what] .sheet__search-input"
    # Sheets open with focus parked on the close button, never the search field.
    refute_focused field

    find(".sheet[data-field=what] .opt--newquery").click
    assert_focused field # the tap moved focus into the search field
  end

  private

  # The filter-sheets controller eager-loads asynchronously, so the very first
  # trigger tap can land before it connects and be ignored. Retry the open until
  # the sheet actually responds — Capybara's has_selector wait does the polling, no
  # fixed sleeps. open() only ever opens (never toggles), so a repeat tap is safe.
  def open_what_sheet
    trigger = find(".filter-sheets .filter-trigger[data-filter-sheets-field-param=what]")
    trigger.click until has_selector?(".sheet[data-field=what].sheet--open", wait: 1)
  end

  # Focus assertions over document.activeElement (reliable headless, unlike the
  # `:focus` CSS pseudo, which can miss when the page lacks system focus), wrapped
  # in Capybara's own retry (synchronize) so they tolerate the brief gap between a
  # click and its handler running — no fixed sleeps.
  def assert_focused(selector)
    page.document.synchronize { raise Capybara::ElementNotFound unless focused?(selector) }
    assert true
  end

  def refute_focused(selector)
    refute focused?(selector)
  end

  def focused?(selector)
    page.evaluate_script(
      "!!document.activeElement && document.activeElement.matches(#{selector.to_json})"
    )
  end
end
