require "db_test_helper"

# ScraperSnooze: a self-expiring, admin-set mute for one scraper.
class ScraperSnoozeTest < ActiveSupport::TestCase
  test "snooze! mutes a scraper for the default window and active_by_slug finds it" do
    ScraperSnooze.snooze!("bad_bonn")

    snooze = ScraperSnooze.active_by_slug.fetch("bad_bonn")
    assert_in_delta ScraperSnooze::DEFAULT_DURATION.from_now, snooze.snoozed_until, 5.seconds
  end

  test "re-snoozing extends the existing row rather than duplicating it" do
    ScraperSnooze.snooze!("bad_bonn", duration: 1.day)
    ScraperSnooze.snooze!("bad_bonn", duration: 2.weeks)

    assert_equal 1, ScraperSnooze.where(scraper: "bad_bonn").count
    assert_in_delta 2.weeks.from_now, ScraperSnooze.sole.snoozed_until, 5.seconds
  end

  test "an expired snooze is not active and prune_expired! removes it" do
    ScraperSnooze.create!(scraper: "docks", snoozed_until: 1.hour.ago)

    assert_empty ScraperSnooze.active
    assert_equal 1, ScraperSnooze.prune_expired!
    assert_equal 0, ScraperSnooze.count
  end

  test "wake! removes the snooze" do
    ScraperSnooze.snooze!("bad_bonn")
    ScraperSnooze.wake!("bad_bonn")

    assert_not ScraperSnooze.active_by_slug.key?("bad_bonn")
  end

  test "prune_expired! leaves a still-active snooze alone" do
    ScraperSnooze.snooze!("bad_bonn")
    ScraperSnooze.prune_expired!

    assert ScraperSnooze.active_by_slug.key?("bad_bonn")
  end
end
