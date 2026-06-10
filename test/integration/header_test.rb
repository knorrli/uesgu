require 'db_test_helper'

# Header layout: a light bar (wordmark + account menu) with the unread signal
# preserved as a dot on the menu trigger.
class HeaderTest < ActionDispatch::IntegrationTest
  test 'the account menu shows an unread dot only when notifications are unread' do
    member = user
    sign_in_as member

    get root_path
    assert_select 'summary .unread-dot', false, 'no dot when nothing is unread'

    member.notifications.create!(period_start: 1.week.ago, period_end: Time.current)
    get root_path
    assert_select 'summary .unread-dot', 1, 'dot appears once there is an unread notification'
  end

  test 'Notifications lives inside the account menu, not as a top-level nav link' do
    sign_in_as user
    get root_path
    assert_select '.nav-menu__items a[href=?]', notifications_path, 1
    assert_select '.site-nav > a[href=?]', notifications_path, false
  end
end
