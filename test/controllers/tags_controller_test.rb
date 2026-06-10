require 'db_test_helper'

# The gear icon on a genre tag in the event list opens the shared genre editor
# through TagsController#edit. Regression net for the 500 where #edit didn't
# assign @alias_suggestions, so genres/_editor raised on an undefined local.
class TagsControllerTest < ActionDispatch::IntegrationTest
  test 'edit renders the shared genre editor for a genre tag' do
    sign_in_as(user(admin: true))

    tagged = event_with_genres('zorptronic')
    tag = ActsAsTaggableOn::Tag.find_by!(name: tagged.genre_list.first)

    get edit_tag_path(tag)

    assert_response :success
  end
end
