require "application_system_test_case"

class GenreExclusionTest < ApplicationSystemTestCase
  test "excluding a genre from its tag takes the event out of the feed and says so" do
    hated = genre(name: "Sysexhated")
    event(start_date: Date.current + 2, title: "HatedShow", genre_list: [hated.name])
    event(start_date: Date.current + 2, title: "LikedShow", genre_list: [genre(name: "Sysexliked").name])
    sign_in_as user

    visit events_path
    find(".event", text: "HatedShow").find(".event-genre form[action='#{genre_exclusions_path}'] button").click

    assert_selector ".day-summary__count--excluded[href='#{settings_path(anchor: 'excluded-genres')}']", text: "1"
    assert_selector ".event", text: "LikedShow"
    assert_no_selector ".event", text: "HatedShow"
  end
end
