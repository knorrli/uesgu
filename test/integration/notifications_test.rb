require "db_test_helper"

class NotificationsTest < ActionDispatch::IntegrationTest
  test "index lists the users digests by name" do
    u = user
    sign_in_as u
    e = event(start_date: Date.current + 2)
    u.notifications.create!(title: "My alert", event_ids: [e.id],
                            period_start: 1.week.ago, period_end: Time.current)

    get notifications_path
    assert_response :success
    assert_select ".notification__name", text: /My alert/
    assert_select ".inbox-tabs", false
  end

  test "index shows each digests own event count" do
    u = user
    sign_in_as u
    e1 = event(start_date: Date.current + 1)
    e2 = event(start_date: Date.current + 2)
    u.notifications.create!(title: "D", event_ids: [e1.id, e2.id],
                            period_start: 1.week.ago, period_end: Time.current)

    get notifications_path
    assert_response :success
    assert_select ".notification__meta", text: /2 Events/
  end

  test "index event count drops events hidden after the digest fired" do
    u = user
    sign_in_as u
    shown = event(start_date: Date.current + 1)
    hidden = event(start_date: Date.current + 2, hidden: true)
    u.notifications.create!(title: "D", event_ids: [shown.id, hidden.id],
                            period_start: 1.week.ago, period_end: Time.current)

    get notifications_path
    assert_response :success
    assert_select ".notification__meta", text: /1 Event/
  end

  test "index splits unread and read into two tabs (Ungelesen | Gelesen)" do
    u = user
    sign_in_as u
    e = event(start_date: Date.current + 2)
    read = u.notifications.create!(title: "Old read", event_ids: [e.id],
                                   period_start: 1.week.ago, period_end: Time.current,
                                   read_at: 1.day.ago)
    unread = u.notifications.create!(title: "Fresh", event_ids: [e.id],
                                     period_start: 1.week.ago, period_end: Time.current)

    get notifications_path
    assert_response :success
    assert_select ".notification__name", text: /Fresh/
    assert_select ".notification__name", text: /Old read/, count: 0
    assert_select ".view-switcher .view-switch__item[href=?]", notifications_path
    assert_select ".view-switcher .view-switch__item[href=?]", notifications_path(read: 1)

    get notifications_path(read: 1)
    assert_response :success
    assert_select ".notification__name", text: /Old read/
    assert_select ".notification__name", text: /Fresh/, count: 0
    assert_select ".view-switcher .view-switch__item[href=?]", notifications_path(read: 1)
    assert_not_nil read && unread
  end

  test "index orders digests newest received first" do
    u = user
    sign_in_as u
    e = event(start_date: Date.current + 2)
    older = u.notifications.create!(title: "Older", event_ids: [e.id],
                                    period_start: 1.week.ago, period_end: Time.current,
                                    created_at: 2.days.ago)
    newer = u.notifications.create!(title: "Newer", event_ids: [e.id],
                                    period_start: 1.week.ago, period_end: Time.current,
                                    created_at: 1.hour.ago)

    get notifications_path
    assert_response :success
    names = css_select(".notification__name").map { |n| n.text.strip }
    assert_operator names.index { |t| t.include?("Newer") },
                    :<, names.index { |t| t.include?("Older") }
    assert_not_nil older && newer
  end

  test "index shows an all-read message when everything is read" do
    u = user
    sign_in_as u
    e = event(start_date: Date.current + 2)
    u.notifications.create!(title: "Read", event_ids: [e.id],
                            period_start: 1.week.ago, period_end: Time.current,
                            read_at: 1.day.ago)

    get notifications_path
    assert_response :success
    assert_select ".empty-state", text: /Alles gelesen/
    assert_select ".view-switcher .view-switch__item[href=?]", notifications_path(read: 1)
  end

  test "mark_all_read clears the whole unread slice" do
    u = user
    sign_in_as u
    e = event(start_date: Date.current + 2)
    a = u.notifications.create!(title: "One", event_ids: [e.id],
                                period_start: 1.week.ago, period_end: Time.current)
    b = u.notifications.create!(title: "Two", event_ids: [e.id],
                                period_start: 1.week.ago, period_end: Time.current)

    post mark_all_read_notifications_path

    assert_redirected_to notifications_path
    assert a.reload.read?
    assert b.reload.read?
  end

  test "mark_all_read leaves already-read digests read_at untouched" do
    u = user
    sign_in_as u
    e = event(start_date: Date.current + 2)
    was_read_at = 3.days.ago
    read = u.notifications.create!(title: "Old", event_ids: [e.id],
                                  period_start: 1.week.ago, period_end: Time.current,
                                  read_at: was_read_at)

    post mark_all_read_notifications_path

    assert_in_delta was_read_at, read.reload.read_at, 1.second
  end

  test "mark_all_read only touches the signed-in users digests" do
    mine = user
    theirs = user
    e = event(start_date: Date.current + 2)
    other = theirs.notifications.create!(title: "Not mine", event_ids: [e.id],
                                         period_start: 1.week.ago, period_end: Time.current)
    sign_in_as mine

    post mark_all_read_notifications_path

    assert_not other.reload.read?
  end

  test "the mark-all-read button is offered only where there is unread to clear" do
    u = user
    sign_in_as u
    e = event(start_date: Date.current + 2)
    digest = u.notifications.create!(title: "Fresh", event_ids: [e.id],
                                     period_start: 1.week.ago, period_end: Time.current)

    get notifications_path
    assert_select "form[action=?]", mark_all_read_notifications_path

    get notifications_path(read: 1)
    assert_select "form[action=?]", mark_all_read_notifications_path, count: 0

    digest.mark_read!
    get notifications_path
    assert_select "form[action=?]", mark_all_read_notifications_path, count: 0
  end

  test "mark_all_read requires authentication" do
    post mark_all_read_notifications_path
    assert_redirected_to new_session_path
  end

  test "show marks the digest read" do
    u = user
    sign_in_as u
    digest = u.notifications.create!(title: "D", event_ids: [event.id],
                                     period_start: 2.days.ago, period_end: Time.current)

    get notification_path(digest)

    assert_response :success
    assert digest.reload.read?
  end

  test "notifications require authentication" do
    get notifications_path
    assert_redirected_to new_session_path
  end
end
