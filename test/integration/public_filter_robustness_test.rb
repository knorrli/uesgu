require "db_test_helper"

# The public events filter surfaces must not 500 on hostile or empty input.
class PublicFilterRobustnessTest < ActionDispatch::IntegrationTest
  test "a search query with regex metacharacters does not crash the events index" do
    # Title matches the "(" query so the card renders; a genre tag exercises the
    # genre-highlight code path that used to build a Regexp from the raw query.
    e = event(title: "Show (Live)")
    e.genre_list = ["Rock"]
    e.save!

    get events_path(q: ["("])

    assert_response :success
    assert_select "article.event", minimum: 1
  end

  test "the tags chips endpoint tolerates a missing combobox_values param" do
    post chips_tags_path, as: :turbo_stream
    assert_response :success
  end
end
