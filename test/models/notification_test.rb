require 'db_test_helper'

class NotificationTest < ActiveSupport::TestCase
  # Locks Notification.visible_event_counts — the batched inbox count that
  # replaced a per-notification N+1. It must still honour #events' "currently
  # visible" rule (an event hidden after the digest fired drops out) and key the
  # result by notification id.
  test 'visible_event_counts counts only currently-visible snapshot events' do
    u = user
    shown = event(start_date: Date.current + 1)
    hidden = event(start_date: Date.current + 2, hidden: true)
    both = u.notifications.create!(title: 'A', event_ids: [shown.id, hidden.id],
                                  period_start: 1.week.ago, period_end: Time.current)
    one = u.notifications.create!(title: 'B', event_ids: [shown.id],
                                 period_start: 1.week.ago, period_end: Time.current)

    counts = Notification.visible_event_counts([both, one])

    assert_equal 1, counts[both.id], 'the hidden event must not be counted'
    assert_equal 1, counts[one.id]
  end

  test 'visible_event_counts returns an empty hash for an empty batch' do
    assert_equal({}, Notification.visible_event_counts([]))
  end
end
