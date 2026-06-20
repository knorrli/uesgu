require 'db_test_helper'

# Locks the notifications inbox: the index lists the user's digests with their
# name + event count, and show marks a digest read. (Digests are created by
# SavedFilter#fire!, not lazily on visit.)
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
    # The inbox is its own standalone section now — no Eingang/Filter tabs.
    assert_select '.inbox-tabs', false
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

  test 'index hides read digests by default and reveals them via the toggle' do
    u = user
    sign_in_as u
    e = event(start_date: Date.current + 2)
    read = u.notifications.create!(title: 'Old read', event_ids: [e.id],
                                   period_start: 1.week.ago, period_end: Time.current,
                                   read_at: 1.day.ago)
    unread = u.notifications.create!(title: 'Fresh', event_ids: [e.id],
                                     period_start: 1.week.ago, period_end: Time.current)

    get notifications_path
    assert_response :success
    assert_select '.notification__name', text: /Fresh/
    assert_select '.notification__name', text: /Old read/, count: 0
    # The toggle advertises the hidden read count and links to ?read=1.
    assert_select 'a.notifications__read-toggle[href=?]', notifications_path(read: 1)

    get notifications_path(read: 1)
    assert_response :success
    assert_select '.notification__name', text: /Old read/
    assert_select '.notification__name', text: /Fresh/
    assert_select 'a.notifications__read-toggle[href=?]', notifications_path
    assert_not_nil read && unread
  end

  test 'index orders digests newest received first' do
    u = user
    sign_in_as u
    e = event(start_date: Date.current + 2)
    # period_end is identical; created_at is what should drive the order.
    older = u.notifications.create!(title: 'Older', event_ids: [e.id],
                                    period_start: 1.week.ago, period_end: Time.current,
                                    created_at: 2.days.ago)
    newer = u.notifications.create!(title: 'Newer', event_ids: [e.id],
                                    period_start: 1.week.ago, period_end: Time.current,
                                    created_at: 1.hour.ago)

    get notifications_path
    assert_response :success
    names = css_select('.notification__name').map { |n| n.text.strip }
    assert_operator names.index { |t| t.include?('Newer') },
                    :<, names.index { |t| t.include?('Older') }
    assert_not_nil older && newer
  end

  test 'index shows an all-read message when everything is read' do
    u = user
    sign_in_as u
    e = event(start_date: Date.current + 2)
    u.notifications.create!(title: 'Read', event_ids: [e.id],
                            period_start: 1.week.ago, period_end: Time.current,
                            read_at: 1.day.ago)

    get notifications_path
    assert_response :success
    assert_select '.empty-state', text: /Alles gelesen/
    assert_select 'a.notifications__read-toggle'
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
