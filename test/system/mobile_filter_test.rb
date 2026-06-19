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

  # ~300 in-use genres is too many to browse, so the What sheet hides them until
  # the search box matches one — then picking it commits a q[] substring filter
  # (mirroring the desktop What dropdown). Curated styles stay browsable at rest.
  test "What sheet search-gates genre suggestions and applies a pick as q[]" do
    e = event(start_date: Date.current + 3, style_list: ["Zynthwave"], genre_list: ["Zylodrone"])
    style = e.style_list.first   # read back: genre_list= canonicalizes casing
    genre = e.genre_list.first

    page.current_window.resize_to(390, 800) # below the 600px sheet breakpoint
    visit events_path

    open_what_sheet
    # At rest: the curated style is a visible browse row; the in-use genre is in the
    # DOM but hidden (.opt--suggest, display:none) until the search reveals it.
    assert_selector ".sheet[data-field=what] .opt", text: style, visible: true
    assert_no_selector ".sheet[data-field=what] .opt--suggest", text: genre, visible: true

    field = find(".sheet[data-field=what] .sheet__search-input")
    field.click # settle focus before typing (open() parks it on the close button)
    field.send_keys(genre[0, 4].downcase) # case-insensitive substring match
    assert_selector ".sheet[data-field=what] .opt--suggest", text: genre, visible: true

    find(".sheet[data-field=what] .opt--suggest", text: genre).click
    find(".sheet[data-field=what] .sheet__apply").click

    # Server-rendered chip proves the genre round-tripped as a q[] filter.
    assert_selector ".filter-sheets__summary .filter-chip", text: genre
    assert_current_path(/q%5B%5D=/)
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
end
