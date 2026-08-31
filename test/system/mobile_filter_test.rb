require "application_system_test_case"

class MobileFilterTest < ApplicationSystemTestCase
  test "Enter in the What sheet commits the typed text as a free-text query" do
    event(start_date: Date.current + 3, genre_list: ["Rock"])

    page.current_window.resize_to(390, 800)
    visit events_path

    open_what_sheet
    field = find(".sheet[data-field=what] .sheet__search-input")
    field.click
    field.send_keys("zzqx")
    assert_selector ".sheet[data-field=what] .opt--newquery", text: /zzqx/
    field.send_keys(:enter)

    assert_current_path(/q%5B%5D=zzqx/)
    assert_selector ".filter-sheets__summary .filter-chip", text: "zzqx"
  end

  test "What sheet renders the genre tree and applies a genre pick as g[]" do
    rock = genre(name: "Zylorock", events_count: 1)
    shoegaze = genre(name: "Zyloshoe", events_count: 1)
    shoegaze.set_parent!(rock)
    e = event(start_date: Date.current + 3, genre_list: [shoegaze.name])

    page.current_window.resize_to(390, 800)
    visit events_path

    open_what_sheet
    assert_selector ".sheet[data-field=what] .opt--top", text: rock.name, visible: true

    checked = ".sheet[data-field=what] input[value='#{rock.name}']:checked"
    10.times do
      find(".sheet[data-field=what] .opt--top", text: rock.name).click
      break if has_selector?(checked, visible: :all, wait: 1)
    end
    assert_selector checked, visible: :all

    find(".sheet[data-field=what] .sheet__apply").click

    assert_selector ".filter-sheets__summary .filter-chip", text: rock.name
    assert_current_path(/g%5B%5D=/)
    assert_text e.title
  end

  test "tapping the blank type-to-search hint focuses the What search field" do
    event(start_date: Date.current + 3, genre_list: ["Zynthwave"])

    page.current_window.resize_to(390, 800)
    visit events_path

    open_what_sheet
    field = ".sheet[data-field=what] .sheet__search-input"
    refute_focused field

    newquery = ".sheet[data-field=what] .opt--newquery"
    10.times do
      find(newquery).click
      break if focused?(field)
    end
    assert_focused field
  end

  private

  def open_what_sheet
    trigger = find(".filter-sheets .filter-trigger[data-filter-sheets-field-param=what]")
    trigger.click until has_selector?(".sheet[data-field=what].sheet--open", wait: 1)
  end

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
