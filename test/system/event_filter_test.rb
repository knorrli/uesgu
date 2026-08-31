require "application_system_test_case"

class EventFilterTest < ApplicationSystemTestCase
  test "picking a genre applies a tree-expanding g[] filter" do
    rock = genre(name: "Zylorock", events_count: 1)
    shoegaze = genre(name: "Zyloshoe", events_count: 1)
    shoegaze.set_parent!(rock)
    e = event(start_date: Date.current + 3, genre_list: [shoegaze.name])

    visit events_path
    open_sheet("what")

    find(".sheet[data-field=what] .opt--top", text: rock.name).click
    assert_selector ".sheet[data-field=what] input[value='#{rock.name}']:checked", visible: :all
    find(".sheet[data-field=what] .sheet__apply").click

    assert_current_path(/g%5B%5D=#{Regexp.escape(rock.name)}/)
    assert_selector ".filter-sheets__summary .filter-chip", text: rock.name
    assert_text e.title
  end

  test "removing the genre chip clears the filter" do
    rock = genre(name: "Zylorock", events_count: 1)
    child = genre(name: "Zylokid", events_count: 1)
    child.set_parent!(rock)
    event(start_date: Date.current + 3, genre_list: [child.name])

    visit events_path("g[]": rock.name)
    10.times do
      break if has_no_current_path?(/g%5B%5D=/, wait: 0.5)
      find(".filter-sheets__summary .filter-chip", text: rock.name).click
    end

    assert_no_current_path(/g%5B%5D=/)
  end

  test "removing one chip keeps a filter whose sheet was never opened" do
    rock = genre(name: "Zylokeep", events_count: 1)
    child = genre(name: "Zylokidkeep", events_count: 1)
    child.set_parent!(rock)
    event(start_date: Date.current + 3, genre_list: [child.name], title: "Zzqxshow")

    visit events_path("g[]": rock.name, "q[]": "Zzqx")
    10.times do
      break if has_no_current_path?(/q%5B%5D=/, wait: 0.5)
      find(".filter-sheets__summary .filter-chip", text: "Zzqx").click
    end

    assert_no_current_path(/q%5B%5D=/)
    assert_current_path(/g%5B%5D=#{Regexp.escape(rock.name)}/)
    assert_selector ".filter-sheets__summary .filter-chip", text: rock.name
  end

  test "tapping a genre on an event row filters by it (g[]) and lights it" do
    rock = genre(name: "Taprock", events_count: 1)
    shoegaze = genre(name: "Tapshoe", events_count: 1)
    shoegaze.set_parent!(rock)
    event(start_date: Date.current + 3, genre_list: [shoegaze.name])

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
    field.click
    field.send_keys("zzqx")
    assert_selector ".sheet[data-field=what] .opt--newquery", text: /zzqx/, visible: :all
    field.send_keys(:enter)

    assert_current_path(/q%5B%5D=zzqx/)
    assert_selector ".filter-sheets__summary .filter-chip", text: "zzqx"
  end

  test "clicking Apply commits typed text not submitted with Enter or the row" do
    event(start_date: Date.current + 3, genre_list: ["Zylogenre"])

    visit events_path
    open_sheet("what")
    field = find(".sheet[data-field=what] .sheet__search-input")
    field.click
    field.send_keys("wubz")
    assert_selector ".sheet[data-field=what] .opt--newquery", text: /wubz/, visible: :all
    find(".sheet[data-field=what] .sheet__apply").click

    assert_current_path(/q%5B%5D=wubz/)
    assert_selector ".filter-sheets__summary .filter-chip", text: "wubz"
  end

  test "a filter panel closes via its × and via click-outside (desktop)" do
    rock = genre(name: "Closerock", events_count: 1)
    genre(name: "Closekid", events_count: 1).set_parent!(rock)
    event(start_date: Date.current + 3, genre_list: ["Closekid"])
    visit events_path

    open_sheet("what")
    find(".sheet[data-field=what] .sheet__close").click
    assert_no_selector ".sheet[data-field=what].sheet--open"

    open_sheet("what")
    find("body").trigger("click")
    assert_no_selector ".sheet[data-field=what].sheet--open"
  end

  private

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
