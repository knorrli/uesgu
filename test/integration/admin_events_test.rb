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
end
