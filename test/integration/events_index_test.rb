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

  test 'a location filter narrows the listing' do
    event(title: 'AlphaShow', location_list: ['VenueAlpha'], start_date: Date.current + 2.days)
    event(title: 'BetaShow', location_list: ['VenueBeta'], start_date: Date.current + 2.days)

    get events_path(l: 'VenueAlpha')

    assert_response :success
    assert_includes response.body, 'AlphaShow'
    refute_includes response.body, 'BetaShow'
  end

  test 'a text query filters by title' do
    event(title: 'FindMeUnique', start_date: Date.current + 2.days)
    event(title: 'OtherUnique', start_date: Date.current + 2.days)

    get events_path(q: ['FindMeUnique'])

    assert_includes response.body, 'FindMeUnique'
    refute_includes response.body, 'OtherUnique'
  end

  test 'the default date floor hides past events' do
    event(title: 'PastShow', start_date: Date.current - 10.days)
    event(title: 'FutureShow', start_date: Date.current + 10.days)

    get events_path

    assert_includes response.body, 'FutureShow'
    refute_includes response.body, 'PastShow'
  end

  test 'the chosen view is mirrored onto the logged-in users account' do
    u = sign_in_as user
    get events_path(view: 'calendar')
    assert_equal 'calendar', u.reload.events_view

    get events_path(view: 'nonsense') # invalid falls back to list
    assert_equal 'list', u.reload.events_view
  end
end
