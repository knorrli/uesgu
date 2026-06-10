require 'db_test_helper'

# Locks the notifications endpoints: index lazily seals due digests, and show
# marks the digest read.
class NotificationsTest < ActionDispatch::IntegrationTest
  test 'index lazily seals digests that came due since last visit' do
    u = user(notification_frequency: 'daily', created_at: 2.days.ago)
    event(created_at: 30.hours.ago)
    sign_in_as u

    assert_difference -> { u.notifications.count }, 1 do
      get notifications_path
    end
    assert_response :success
  end

  test 'show marks the digest read' do
    u = user
    sign_in_as u
    digest = u.notifications.create!(period_start: 2.days.ago, period_end: 1.day.ago)

    get notification_path(digest)

    assert_response :success
    assert digest.reload.read?
  end

  test 'notifications require authentication' do
    get notifications_path
    assert_redirected_to new_session_path
  end
end
