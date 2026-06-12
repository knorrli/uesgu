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

  # The favorites shortcut is rendered for any logged-in user but hidden until
  # they follow something, so the favorite Stimulus controller can reveal it on
  # the first favorite without a reload (it can only toggle a node that exists).
  test 'favorites shortcut is absent for guests, hidden with no follows, shown once following' do
    get events_path
    assert_select 'a.favorites-filter-link', false, 'guests never see the favorites shortcut'

    u = sign_in_as user
    get events_path
    assert_select 'a.favorites-filter-link[hidden]', 1,
                  'a logged-in user with no follows gets it rendered but hidden'

    u.update!(location_list: ['Dachstock'])
    get events_path
    assert_select 'a.favorites-filter-link:not([hidden])', 1,
                  'once the user follows something the shortcut is shown'
  end

  test 'the chosen view is mirrored onto the logged-in users account' do
    u = sign_in_as user
    get events_path(view: 'calendar')
    assert_equal 'calendar', u.reload.events_view

    get events_path(view: 'nonsense') # invalid falls back to list
    assert_equal 'list', u.reload.events_view
  end

  test 'the admin delete button dismisses (soft-delete): gone from public, kept in DB' do
    e = event(title: 'DismissMeShow', start_date: Date.current + 3.days)
    sign_in_as user(admin: true)

    delete event_path(e)
    assert_redirected_to events_path

    assert e.reload.dismissed?, 'event should be soft-deleted, not destroyed'
    assert Event.exists?(e.id), 'row should remain in the DB'

    get events_path
    assert_not_includes @response.body, 'DismissMeShow'
  end

  test 'non-admins cannot dismiss events' do
    e = event(title: 'KeepMeShow', start_date: Date.current + 3.days)
    sign_in_as user(admin: false)

    delete event_path(e)
    assert_response :forbidden
    refute e.reload.dismissed?
  end
end
