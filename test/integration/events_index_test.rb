require 'db_test_helper'

# Locks the public events listing: it's reachable without auth and only renders
# visible (non-hidden) events.
class EventsIndexTest < ActionDispatch::IntegrationTest
  test 'index is public and shows visible events but not hidden ones' do
    event(title: 'VisibleMarkerShow', start_date: Date.current + 3.days)
    event(title: 'HiddenMarkerShow', start_date: Date.current + 3.days, hidden: true)

    get events_path

    assert_response :success
    assert_includes response.body, 'VisibleMarkerShow'
    refute_includes response.body, 'HiddenMarkerShow'
  end

  test 'calendar view renders' do
    sign_in_as user
    get events_path(view: 'calendar')
    assert_response :success
  end
end
