require "application_system_test_case"

class DayNavTest < ApplicationSystemTestCase
  setup do
    @first = Date.current + 1
    @second = Date.current + 2
    @third = Date.current + 4
    [@first, @second, @third].each { |date| event(start_date: date, genre_list: ["Rock"]) }
  end

  test "the arrows move a day at a time, and back returns to the day before" do
    visit events_path
    assert_selector "h2[id='#{@first.iso8601}']"

    find(".day-nav a[rel=next]").click
    assert_selector "h2[id='#{@second.iso8601}']"
    assert_current_path events_path(day: @second.iso8601)

    go_back
    assert_selector "h2[id='#{@first.iso8601}']"
  end

  test "the calendar offers only days with events and jumps to the picked one" do
    visit events_path(day: @second.iso8601)

    calendar = ".day-nav__calendar"
    trigger = find(".day-nav button[popovertarget]")
    trigger.click until has_selector?("#{calendar} .range-cal__day", minimum: 28, wait: 1)

    assert_selector "#{calendar} .range-cal__day.is-start[data-date='#{@second.iso8601}']"
    assert_selector "#{calendar} .range-cal__day[data-date='#{(@second + 1).iso8601}'][disabled]"

    target = "#{calendar} .range-cal__day[data-date='#{@third.iso8601}']"
    find(target).click until has_selector?("h2[id='#{@third.iso8601}']", wait: 1)
    assert_current_path events_path(day: @third.iso8601)
  end
end
