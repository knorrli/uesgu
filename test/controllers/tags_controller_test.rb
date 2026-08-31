require "db_test_helper"

class TagsControllerTest < ActionDispatch::IntegrationTest
  test "edit renders the shared genre editor for a genre tag" do
    sign_in_as(user(admin: true))

    tagged = event_with_genres("zorptronic")
    tag = ActsAsTaggableOn::Tag.find_by!(name: tagged.genre_list.first)

    get edit_tag_path(tag)

    assert_response :success
  end
end
