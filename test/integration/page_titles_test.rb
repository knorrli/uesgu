require 'db_test_helper'

# The layout composes "<page> — üsgu" from a page's content_for(:title), falling
# back to bare "üsgu". Locks that the brand suffix lives in one place
# (app/views/layouts/application.html.erb) and isn't doubled or dropped.
class PageTitlesTest < ActionDispatch::IntegrationTest
  test 'the home/listing page tab is just the brand (sets no title), never doubled' do
    get events_path
    assert_select 'title', text: 'üsgu'
    assert_no_match(/üsgu — üsgu/, response.body, 'the brand is never doubled')
  end

  test 'a page that sets a title gets the brand suffix appended exactly once' do
    get new_session_path # login — had no title before, now composed
    assert_select 'title', /\A.+ — üsgu\z/
    assert_no_match(/üsgu — üsgu/, response.body)
  end
end
