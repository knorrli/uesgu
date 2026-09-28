require "db_test_helper"

class GenresHelperTest < ActionView::TestCase
  test "shown_genres leaves out ignored genres and their aliases" do
    broad = genre(name: "all-styles")
    variant = genre(name: "allstyle")
    variant.merge_into!(broad)
    broad.ignore!
    event = event_with_genres(broad.name, variant.name, "glimmercore")

    assert_equal ["Glimmercore"], shown_genres(event).map(&:name)
  end
end
