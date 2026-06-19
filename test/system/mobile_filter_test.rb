require "application_system_test_case"

# The mobile filter sheets (<600px). Companion to event_filter_test.rb, which
# covers the desktop combobox; here we exercise the full-screen What sheet.
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

  # The What sheet lists in-use genres (q[]) alongside the curated styles (s[]),
  # browsable like the desktop What dropdown; picking a genre commits a q[]
  # substring filter. The search box filters the (long) list.
  test "What sheet lists genres and applies a genre pick as q[]" do
    e = event(start_date: Date.current + 3, style_list: ["Zynthwave"], genre_list: ["Zylodrone"])
    style = e.style_list.first   # read back: genre_list= canonicalizes casing
    genre = e.genre_list.first

    page.current_window.resize_to(390, 800) # below the 600px sheet breakpoint
    visit events_path

    open_what_sheet
    # Both the curated style and the in-use genre are visible browse rows at rest.
    assert_selector ".sheet[data-field=what] .opt", text: style, visible: true
    assert_selector ".sheet[data-field=what] .opt", text: genre, visible: true

    # Narrow with the search box (what you'd do with a long list), then pick the
    # genre — commits q[]. Waiting on :checked avoids racing the click.
    field = find(".sheet[data-field=what] .sheet__search-input")
    field.click # settle focus before typing (open() parks it on the close button)
    field.send_keys(genre[0, 4].downcase) # case-insensitive substring match
    find(".sheet[data-field=what] .opt", text: genre, visible: true).click
    assert_selector ".sheet[data-field=what] input[value='#{genre}']:checked", visible: :all

    find(".sheet[data-field=what] .sheet__apply").click

    # Server-rendered chip proves the genre round-tripped as a q[] filter.
    assert_selector ".filter-sheets__summary .filter-chip", text: genre
    assert_current_path(/q%5B%5D=/)
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
