require "application_system_test_case"

class MobileDateFilterTest < ApplicationSystemTestCase
  test "When sheet calendar picks a custom range and applies it as a d[] filter" do
    start_day = Date.current.beginning_of_month + 9
    end_day   = Date.current.beginning_of_month + 19
    event(start_date: start_day + 1, genre_list: ["Rock"])

    page.current_window.resize_to(390, 800)
    visit events_path

    open_when_sheet
    sheet = ".sheet[data-field=when]"
    assert_selector "#{sheet} .range-cal__day", minimum: 28

    start_sel    = "#{sheet} .range-cal__day[data-date='#{start_day.iso8601}']"
    start_picked = "#{sheet} .range-cal__day.is-start[data-date='#{start_day.iso8601}']"
    find(start_sel).click until has_selector?(start_picked, wait: 1)

    find("#{sheet} .range-cal__day[data-date='#{end_day.iso8601}']").click
    assert_selector "#{sheet} .range-cal__day.is-end[data-date='#{end_day.iso8601}']"

    find("#{sheet} .sheet__apply").click

    assert_current_path(/d%5B%5D=#{start_day.iso8601}.*#{end_day.iso8601}/)
    label = "#{I18n.l(start_day)} - #{I18n.l(end_day)}"
    assert_selector ".filter-sheets__summary .filter-chip", text: label
  end

  private

  def open_when_sheet
    trigger = find(".filter-sheets .filter-trigger[data-filter-sheets-field-param=when]")
    trigger.click until has_selector?(".sheet[data-field=when].sheet--open", wait: 1)
  end
end
