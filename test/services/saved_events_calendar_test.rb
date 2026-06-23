require "db_test_helper"

# Locks the ICS feed of a user's saved shows: timed vs all-day handling (incl.
# the unknown-time → all-day rule), the yesterday-onward window, cancellation,
# and per-user scoping. Synthetic events only (taxonomy rule in db_test_helper).
class SavedEventsCalendarTest < ActiveSupport::TestCase
  def saved(owner, **attrs)
    e = event(**attrs)
    owner.event_saves.create!(event: e)
    e
  end

  def at(date, hour:, min: 0)
    date.in_time_zone.change(hour: hour, min: min)
  end

  test "a timed show is a timed VEVENT in UTC (Z-marked, not floating)" do
    u = user
    saved(u, title: "Timed Show", start_date: Date.current + 5,
             start_time: at(Date.current + 5, hour: 20, min: 30))
    ics = SavedEventsCalendar.ics(u)
    assert_includes ics, "SUMMARY:Timed Show"
    assert_match(/DTSTART:\d{8}T\d{6}Z/, ics)
  end

  test "a show with no time becomes an all-day entry" do
    u = user
    saved(u, title: "Untimed Show", start_date: Date.current + 5, start_time: nil)
    assert_match(/DTSTART;VALUE=DATE:\d{8}/, SavedEventsCalendar.ics(u))
  end

  test "an exact midnight time is treated as unknown — all-day, never 00:00" do
    u = user
    saved(u, title: "Midnight Show", start_date: Date.current + 5,
             start_time: at(Date.current + 5, hour: 0, min: 0))
    ics = SavedEventsCalendar.ics(u)
    assert_match(/DTSTART;VALUE=DATE:/, ics)
    refute_match(/DTSTART:\d{8}T000000/, ics)
  end

  test "drops shows older than yesterday but keeps yesterday" do
    u = user
    saved(u, title: "LongGoneShow", start_date: Date.current - 3)
    saved(u, title: "YesterdayShow", start_date: Date.current - 1)
    ics = SavedEventsCalendar.ics(u)
    refute_includes ics, "LongGoneShow"
    assert_includes ics, "YesterdayShow"
  end

  test "marks a cancelled show cancelled" do
    u = user
    saved(u, title: "Scrapped Show", start_date: Date.current + 2, cancelled_at: Time.current)
    ics = SavedEventsCalendar.ics(u)
    assert_includes ics, "STATUS:CANCELLED"
  end

  test "only the owner saved shows appear" do
    mine = user
    saved(mine, title: "MyShow", start_date: Date.current + 2)
    saved(user, title: "TheirShow", start_date: Date.current + 2)
    ics = SavedEventsCalendar.ics(mine)
    assert_includes ics, "MyShow"
    refute_includes ics, "TheirShow"
  end
end
