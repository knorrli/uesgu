require "db_test_helper"

class PublicFilterRobustnessTest < ActionDispatch::IntegrationTest
  test "a search query with regex metacharacters does not crash the events index" do
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
