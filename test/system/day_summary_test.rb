require "application_system_test_case"

class DaySummaryTest < ApplicationSystemTestCase
  test "the saved count updates live as you save and unsave" do
    event(start_date: Date.current + 2, title: "A", genre_list: ["Rock"])
    sign_in_as user

    visit events_path
    assert_no_selector ".day-summary__count--saved", visible: true

    find(".event-save", match: :first).click
    assert_selector ".day-summary__count--saved", text: "1"

    find(".event-save", match: :first).click
    assert_no_selector ".day-summary__count--saved", visible: true
  end
end
