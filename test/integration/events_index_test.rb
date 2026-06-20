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

  test 'the calendar flags days holding a saved show with a bookmark marker' do
    u = sign_in_as user
    saved = event(start_date: Date.current + 3, title: 'SavedShow')
    event(start_date: Date.current + 5, title: 'UnsavedShow') # different day, not saved
    u.event_saves.create!(event: saved)

    get events_path(view: 'calendar')

    assert_response :success
    # Only the day with the saved show is flagged — not every day with events.
    assert_select 'section.event-calendar .day-saved-marker', count: 1
  end

  test 'guests never see the calendar bookmark marker' do
    event(start_date: Date.current + 3)

    get events_path(view: 'calendar')

    assert_response :success
    assert_select '.day-saved-marker', count: 0
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

  test 'a freetext term lights a genre tag whose name contains it, and tapping clears it' do
    # Title has no "hop"; the row shows up (and its tag lights) purely on the
    # genre-name substring — proving freetext now drives genre-tag highlighting,
    # not just the genre-tree filter.
    event(title: 'NoMatchTitle', genre_list: ['Quophop'], start_date: Date.current + 2.days)

    get events_path(q: ['hop'])

    assert_response :success
    assert_includes response.body, 'NoMatchTitle' # in the list via genres_name_cont
    # The genre tag is lit, and tapping it drops the freetext term (back to no q).
    assert_select "a.filter-link.active[href=?]", events_path, text: 'Quophop'
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

  test 'the edit gear links to the admin event page, only for admins' do
    e = event(start_date: Date.current + 3.days)

    sign_in_as user(admin: true)
    get events_path
    assert_select "a.icon-button[href=?]", admin_event_path(e)

    sign_in_as user(admin: false)
    get events_path
    assert_select 'a.icon-button', count: 0
  end

  test 'the delete button submits a real DELETE (method override present)' do
    e = event(start_date: Date.current + 3.days)
    sign_in_as user(admin: true)

    get events_path
    # button_to must emit the _method=delete override so the form routes to
    # EventsController#destroy rather than a stray POST (which Turbo treats as a
    # full navigation / "refresh").
    assert_select "form[action=?][method=post]", event_path(e) do
      assert_select "input[type=hidden][name=_method][value=delete]"
    end
  end
end
