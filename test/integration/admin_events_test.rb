require 'db_test_helper'

# Read-only events browser under /admin/events: admin-gated, with visibility
# filters, title search, and sort. The admin sees everything (the public index
# is scoped to :visible).
class AdminEventsTest < ActionDispatch::IntegrationTest
  test 'guests are sent to login, non-admins are forbidden' do
    get admin_events_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get admin_events_path
    assert_response :forbidden
  end

  test 'an admin can browse, filter and search events' do
    event(title: 'Loud Guitars')
    event(title: 'Quiet Reading', hidden: true)
    event(title: 'Called Off', cancelled_at: Time.utc(2030, 1, 1))
    sign_in_as user(admin: true)

    get admin_events_path
    assert_response :success
    assert_select 'a', text: 'Loud Guitars'
    assert_select 'a', text: 'Quiet Reading'

    get admin_events_path(status: 'hidden')
    assert_select 'a', text: 'Quiet Reading'
    assert_select 'a', text: 'Loud Guitars', count: 0

    get admin_events_path(status: 'visible')
    assert_select 'a', text: 'Loud Guitars'
    assert_select 'a', text: 'Quiet Reading', count: 0

    get admin_events_path(status: 'cancelled')
    assert_select 'a', text: 'Called Off'
    assert_select 'a', text: 'Loud Guitars', count: 0

    get admin_events_path(q: 'loud')
    assert_select 'a', text: 'Loud Guitars'
    assert_select 'a', text: 'Called Off', count: 0
  end

  test 'the show page renders the edit form and surfaces locked fields' do
    e = event(title: 'Editable Show')
    e.lock_field!(:title)
    sign_in_as user(admin: true)

    get admin_event_path(e)
    assert_response :success
    assert_select 'input[name=?]', 'event[title]'
    assert_select 'input[name=?]', 'event[date]'
    assert_select 'input[name=?]', 'event[time]'
    # The locked title appears in the "manual overrides" list with a revert form.
    assert_select 'form[action=?]', revert_admin_event_path(e, field: 'title')
  end

  test 'editing an event locks only the fields the admin changed' do
    e = event(title: 'Wrong Title', subtitle: 'Keep Me')
    sign_in_as user(admin: true)

    patch admin_event_path(e), params: { event: {
      title: 'Fixed Title', subtitle: 'Keep Me',
      date: e.start_date.iso8601, time: '20:30'
    } }
    assert_redirected_to admin_event_path(e)

    e.reload
    assert_equal 'Fixed Title', e.title
    assert e.overridden?(:title)
    refute e.overridden?(:subtitle) # resubmitted unchanged → not locked
    # The time went from none → 20:30, so the date/time pair locks together.
    assert e.overridden?(:start_time)
    assert e.overridden?(:start_date)
  end

  test 'update ignores params outside the editable set' do
    e = event(title: 'T')
    original_url = e.url
    sign_in_as user(admin: true)

    patch admin_event_path(e), params: { event: {
      title: 'T', subtitle: '', date: e.start_date.iso8601, time: '',
      url: 'https://evil.test/changed', hidden: true
    } }

    e.reload
    assert_equal original_url, e.url
    refute e.hidden?
    assert_empty e.overridden_fields # nothing editable actually changed
  end

  test 'reverting a locked field releases it back to the scraper' do
    e = event
    e.lock_field!(:title)
    sign_in_as user(admin: true)

    patch revert_admin_event_path(e, field: 'title')
    assert_redirected_to admin_event_path(e)
    refute e.reload.overridden?(:title)
  end

  test 'reverting the schedule releases both date and time' do
    e = event
    e.lock_field!(:start_date)
    e.lock_field!(:start_time)
    sign_in_as user(admin: true)

    patch revert_admin_event_path(e, field: 'start_date')

    e.reload
    refute e.overridden?(:start_date)
    refute e.overridden?(:start_time)
  end

  test 'guests and non-admins cannot edit events' do
    e = event(title: 'Untouched')
    patch admin_event_path(e), params: { event: { title: 'Hacked', date: e.start_date.iso8601 } }
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    patch admin_event_path(e), params: { event: { title: 'Hacked', date: e.start_date.iso8601 } }
    assert_response :forbidden
    assert_equal 'Untouched', e.reload.title
  end
end
