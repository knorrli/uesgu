require "application_system_test_case"

# The date-header relevance counts (♥ saved / ★ interest) update live, no reload:
# the ★ recomputes in favorite_controller when you follow/unfollow, the ♥ is
# adjusted by day_summary_controller when you save/unsave within the day.
class DaySummaryTest < ApplicationSystemTestCase
  test "the interest count updates live as you follow and unfollow" do
    day = Date.current + 2
    event(start_date: day, title: "A", style_list: ["Rock"])
    event(start_date: day, title: "B", style_list: ["Rock"])
    event(start_date: day, title: "C", style_list: ["Jazz"])
    sign_in_as user

    visit events_path
    assert_no_selector ".day-summary__count--interest", visible: true

    follow("Rock") # two shows match
    assert_selector ".day-summary__count--interest", text: "2"

    follow("Rock") # unfollow → gone
    assert_no_selector ".day-summary__count--interest", visible: true
  end

  test "the saved count updates live as you save and unsave" do
    event(start_date: Date.current + 2, title: "A", style_list: ["Rock"])
    sign_in_as user

    visit events_path
    assert_no_selector ".day-summary__count--saved", visible: true

    find(".event-save", match: :first).click
    assert_selector ".day-summary__count--saved", text: "1"

    find(".event-save", match: :first).click
    assert_no_selector ".day-summary__count--saved", visible: true
  end

  private

  # Clicking any matching tag follows/unfollows it page-wide (favorite_controller).
  def follow(value)
    find("button.event-tag.fav[data-favorite-value-param='#{value}']", match: :first).click
  end
end
