require 'db_test_helper'

# Locks the notifications inbox: the index lists the user's digests with their
# name + event count, and show marks a digest read. (Digests are created by
# NotificationRule#fire!, not lazily on visit.)
class NotificationsTest < ActionDispatch::IntegrationTest
  test 'index lists the users digests by name' do
    u = user
    sign_in_as u
    e = event(start_date: Date.current + 2)
    u.notifications.create!(title: 'My alert', event_ids: [e.id],
                            period_start: 1.week.ago, period_end: Time.current)

    get notifications_path
    assert_response :success
    assert_select '.notification__name', text: /My alert/
    # The Inbox tabs tie the messages list and the rules together.
    assert_select '.segmented a.active[href=?]', notifications_path
    assert_select '.segmented a[href=?]', notification_rules_path
  end

  test 'index shows each digests own event count' do
    u = user
    sign_in_as u
    e1 = event(start_date: Date.current + 1)
    e2 = event(start_date: Date.current + 2)
    u.notifications.create!(title: 'D', event_ids: [e1.id, e2.id],
                            period_start: 1.week.ago, period_end: Time.current)

    get notifications_path
    assert_response :success
    assert_select '.notification__meta', text: /2 Veranstaltungen/
  end

  test 'show marks the digest read' do
    u = user
    sign_in_as u
    digest = u.notifications.create!(title: 'D', event_ids: [event.id],
                                     period_start: 2.days.ago, period_end: Time.current)

    get notification_path(digest)

    assert_response :success
    assert digest.reload.read?
  end

  test 'notifications require authentication' do
    get notifications_path
    assert_redirected_to new_session_path
  end
end
