require 'db_test_helper'

# Locks the per-user digest engine: generate_for seals every fully-elapsed
# window since last_notified_at, creating a Notification only for windows that
# actually gained events, and advances the cursor. Also covers the window event
# queries, favorite-narrowing, and read state.
class NotificationTest < ActiveSupport::TestCase
  # Fixed reference clock — generate_for takes an explicit `now:`, so no freezing.
  T0 = Time.utc(2030, 1, 1, 12, 0, 0)

  # --- generate_for ----------------------------------------------------------

  test 'generate_for seals a window that gained events and advances the cursor' do
    u = user(notification_frequency: 'daily', created_at: T0)
    event(created_at: T0 + 6.hours)

    created = Notification.generate_for(u, now: T0 + 1.day + 1.hour)

    assert_equal 1, created.size
    digest = created.first
    assert_equal T0, digest.period_start
    assert_equal T0 + 1.day, digest.period_end
    assert_equal T0 + 1.day, u.reload.last_notified_at
  end

  test 'generate_for skips empty windows but still advances the cursor' do
    u = user(notification_frequency: 'daily', created_at: T0)
    # No events anywhere in the elapsed window.

    created = Notification.generate_for(u, now: T0 + 1.day + 1.hour)

    assert_empty created
    assert_equal T0 + 1.day, u.reload.last_notified_at, 'cursor still moves so we never re-scan the gap'
  end

  test 'generate_for seals each elapsed period independently' do
    u = user(notification_frequency: 'daily', created_at: T0)
    event(created_at: T0 + 2.hours)        # day 1 window
    event(created_at: T0 + 1.day + 2.hours) # day 2 window

    created = Notification.generate_for(u, now: T0 + 2.days + 1.hour)

    assert_equal 2, created.size
    assert_equal [T0, T0 + 1.day], created.map(&:period_start)
  end

  test 'generate_for is idempotent for the same clock' do
    u = user(notification_frequency: 'daily', created_at: T0)
    event(created_at: T0 + 2.hours)
    now = T0 + 1.day + 1.hour

    Notification.generate_for(u, now: now)
    assert_no_difference -> { u.notifications.count } do
      Notification.generate_for(u, now: now)
    end
  end

  test 'generate_for excludes hidden (non-music) events from a window' do
    u = user(notification_frequency: 'daily', created_at: T0)
    event(created_at: T0 + 2.hours, hidden: true)

    created = Notification.generate_for(u, now: T0 + 1.day + 1.hour)

    assert_empty created, 'a hidden event must not seal a digest'
  end

  test 'generate_for with frequency never just advances the cursor, no digests' do
    u = user(notification_frequency: 'never', created_at: T0)
    event(created_at: T0 + 2.hours)

    created = Notification.generate_for(u, now: T0 + 5.days)

    assert_empty created
    assert_equal T0 + 5.days, u.reload.last_notified_at, 'cursor kept current so re-enabling starts fresh'
  end

  test 'generate_for does nothing before a full period has elapsed' do
    u = user(notification_frequency: 'weekly', created_at: T0)
    event(created_at: T0 + 1.hour)

    created = Notification.generate_for(u, now: T0 + 3.days) # < 1 week

    assert_empty created
    assert_nil u.reload.last_notified_at, 'untouched when no window closed; still falls back to created_at'
  end

  # --- events / relevant_events ---------------------------------------------

  test 'events returns only visible events created inside the window, by date' do
    u = user(created_at: T0)
    digest = u.notifications.create!(period_start: T0, period_end: T0 + 1.day)
    late = event(created_at: T0 + 3.hours, start_date: Date.new(2030, 6, 2))
    early = event(created_at: T0 + 1.hour, start_date: Date.new(2030, 6, 1))
    event(created_at: T0 + 2.hours, hidden: true)          # excluded: hidden
    event(created_at: T0 + 2.days)                          # excluded: out of window

    assert_equal [early.id, late.id], digest.events.map(&:id)
  end

  test 'relevant_events narrows to the users favorite locations' do
    u = user(created_at: T0, location_list: ['Invented Venue'])
    digest = u.notifications.create!(period_start: T0, period_end: T0 + 1.day)
    match = event(created_at: T0 + 1.hour, location_list: ['Invented Venue'])
    event(created_at: T0 + 2.hours, location_list: ['Other Place'])

    assert_equal [match.id], digest.relevant_events.map(&:id)
  end

  test 'relevant_events falls back to all window events when no favorites' do
    u = user(created_at: T0)
    digest = u.notifications.create!(period_start: T0, period_end: T0 + 1.day)
    event(created_at: T0 + 1.hour)
    event(created_at: T0 + 2.hours)

    assert_equal 2, digest.relevant_events.count
  end

  # --- read state ------------------------------------------------------------

  test 'mark_read! sets read_at once and is idempotent' do
    u = user
    digest = u.notifications.create!(period_start: T0, period_end: T0 + 1.day)
    refute digest.read?

    digest.mark_read!
    assert digest.read?
    first = digest.read_at

    digest.mark_read!
    assert_equal first, digest.reload.read_at, 'a second mark_read! does not move read_at'
  end
end
