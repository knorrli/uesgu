require "application_system_test_case"

class GenreExclusionTest < ApplicationSystemTestCase
  test "excluding a genre from the event's menu takes the event out of the feed and says so" do
    hated = genre(name: "Sysexhated")
    event(start_date: Date.current + 2, title: "HatedShow", genre_list: [hated.name])
    event(start_date: Date.current + 2, title: "LikedShow", genre_list: [genre(name: "Sysexliked").name])
    sign_in_as user

    visit events_path
    show = find(".event", text: "HatedShow")
    show.find(".exclude-menu summary").click
    show.find(".exclude-menu form[action='#{genre_exclusions_path}'] button", text: "Sysexhated").click

    assert_selector ".day-summary__count--excluded[href='#{settings_path(anchor: 'excluded-genres')}']", text: "1"
    assert_selector ".event", text: "LikedShow"
    assert_no_selector ".event", text: "HatedShow"
  end
end
