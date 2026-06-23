require "db_test_helper"

# Locks the saved-show reminder: due? scheduling + once-a-day guard, the day's
# digest (incl. unknown-time shows, since it fires at a fixed noon), cancelled/
# dismissed exclusion, the day-before lead option, and the run_due! sweep.
class EventReminderTest < ActiveSupport::TestCase
  NOON = Time.zone.local(2030, 6, 3, 12, 0, 0).freeze
  TODAY = NOON.to_date

  def at(hour, min = 0, date: TODAY)
    Time.zone.local(date.year, date.month, date.day, hour, min)
  end

  def reminder_user(**attrs)
    user(**{ event_reminders: true, reminder_time: 12 * 60 }.merge(attrs))
  end

  def save_for(owner, **attrs)
    e = event(**attrs)
    owner.event_saves.create!(event: e)
    e
  end

  # --- due? ------------------------------------------------------------------

  test "due only after the reminder time, and only once a day" do
    u = reminder_user
    refute EventReminder.new(u, at(11)).due?
    assert EventReminder.new(u, at(12)).due?

    u.update_column(:last_reminded_on, TODAY)
    refute EventReminder.new(u, at(13)).due?
  end

  test "a disabled user is never due" do
    refute EventReminder.new(reminder_user(event_reminders: false), at(13)).due?
  end

  # --- firing ----------------------------------------------------------------

  test "fires a digest of today saved shows and marks the day done" do
    u = reminder_user
    today_show = save_for(u, title: "Tonight", start_date: TODAY)
    save_for(u, title: "Next Week", start_date: TODAY + 7)

    note = EventReminder.new(u, at(12, 30)).fire_if_due!
    assert_equal [today_show.id], note.event_ids
    assert_equal TODAY, u.reload.last_reminded_on
  end

  test "an unknown start time still reminds (fires at noon regardless of the show time)" do
    u = reminder_user
    save_for(u, title: "No Time", start_date: TODAY, start_time: nil)
    note = EventReminder.new(u, at(12, 30)).fire_if_due!
    assert_equal 1, note.event_ids.size
  end

  test "skips cancelled and dismissed shows" do
    u = reminder_user
    live = save_for(u, title: "Live", start_date: TODAY)
    save_for(u, title: "Off", start_date: TODAY, cancelled_at: NOON)
    save_for(u, title: "Gone", start_date: TODAY, dismissed_at: NOON)

    note = EventReminder.new(u, at(12, 30)).fire_if_due!
    assert_equal [live.id], note.event_ids
  end

  # A saved show merged into a canonical (canonical_event_id set), or one since
  # hidden/discarded, must not be counted: it's dropped by Notification#events
  # downstream, so counting it here would split the frozen header count from the
  # body/list count (the "3 stehen an" / "2 für dich" mismatch).
  test "skips events excluded from Event.visible (merged duplicate, hidden, discarded)" do
    u = reminder_user
    canonical = save_for(u, title: "Canonical", start_date: TODAY)
    save_for(u, title: "Duplicate", start_date: TODAY, canonical_event_id: canonical.id)
    save_for(u, title: "Hidden", start_date: TODAY, hidden: true)

    note = EventReminder.new(u, at(12, 30)).fire_if_due!
    assert_equal [canonical.id], note.event_ids
  end

  test "with nothing on the day it sends no digest but still marks the day done" do
    u = reminder_user
    save_for(u, title: "Later", start_date: TODAY + 3)

    assert_nil EventReminder.new(u, at(12, 30)).fire_if_due!
    assert_equal TODAY, u.reload.last_reminded_on
  end

  test "a day-before lead targets tomorrow shows" do
    u = reminder_user(reminder_lead_days: 1)
    tomorrow_show = save_for(u, title: "Tomorrow", start_date: TODAY + 1)
    save_for(u, title: "Today", start_date: TODAY)

    note = EventReminder.new(u, at(12, 30)).fire_if_due!
    assert_equal [tomorrow_show.id], note.event_ids
  end

  # --- run_due! --------------------------------------------------------------

  test "run_due! fires enabled due users and is idempotent within the day" do
    u = reminder_user
    save_for(u, title: "Show", start_date: TODAY)
    off = reminder_user(event_reminders: false)
    save_for(off, title: "OffShow", start_date: TODAY)

    created = EventReminder.run_due!(at(12, 30))
    assert_equal 1, created.size
    assert_empty EventReminder.run_due!(at(12, 45)) # already fired today
  end
end
