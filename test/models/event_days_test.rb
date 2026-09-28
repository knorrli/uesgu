require "db_test_helper"

class EventDaysTest < ActiveSupport::TestCase
  setup do
    @today = Date.new(2030, 3, 10)
    [@today - 2, @today + 1, @today + 1, @today + 4].each { |date| event(start_date: date) }
  end

  test "lists each day with an event once, in order" do
    assert_equal [@today - 2, @today + 1, @today + 4], days.dates
  end

  test "opens on the first day from today on" do
    assert_equal @today + 1, days.default
  end

  test "opens on the last day when every day has passed" do
    assert_equal @today + 4, days(today: @today + 10).default
  end

  test "resolves an empty day forward, and past the last day to the last one" do
    assert_equal @today + 1, days.resolve(@today + 1)
    assert_equal @today + 4, days.resolve(@today + 2)
    assert_equal @today + 4, days.resolve(@today + 30)
    assert_equal @today + 1, days.resolve(nil)
  end

  test "steps over empty days in both directions" do
    assert_equal @today + 4, days.after(@today + 1)
    assert_equal @today - 2, days.before(@today + 1)
    assert_nil days.after(@today + 4)
    assert_nil days.before(@today - 2)
  end

  test "counts only the days of the relation it is given" do
    assert_equal [@today + 4], days(Event.where(start_date: @today + 3..)).dates
  end

  test "has nothing to open on without events" do
    empty = days(Event.none)

    refute empty.any?
    assert_nil empty.default
    assert_nil empty.resolve(@today)
  end

  private

  def days(events = Event.all, today: @today)
    EventDays.new(events, today: today)
  end
end
