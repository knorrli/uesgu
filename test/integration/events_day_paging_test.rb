require "db_test_helper"

class EventsDayPagingTest < ActionDispatch::IntegrationTest
  setup do
    @first = Date.current + 1
    @second = Date.current + 4
    event(title: "FirstDayShow", start_date: @first)
    event(title: "SecondDayShow", start_date: @second)
  end

  test "the feed opens on the first day with events and shows that day only" do
    get events_path

    assert_response :success
    assert_includes response.body, "FirstDayShow"
    refute_includes response.body, "SecondDayShow"
    assert_select ".date__label", count: 1
  end

  test "the date header abbreviates the weekday and the year" do
    sign_in_as user(locale: "de")
    event(title: "WednesdayShow", start_date: Date.new(2030, 1, 2))

    get events_path(day: "2030-01-02")

    assert_select ".date__label", text: "Mi, 02.01.30"
  end

  test "the arrows step over empty days and stop at the ends" do
    get events_path

    assert_select ".day-nav a[rel=next][href=?]", events_path(day: @second.iso8601)
    assert_select ".day-nav a[rel=prev]", false
    assert_select ".day-nav .is-disabled .ph-caret-left"

    get events_path(day: @second.iso8601)

    assert_includes response.body, "SecondDayShow"
    assert_select ".day-nav a[rel=prev][href=?]", events_path(day: @first.iso8601)
    assert_select ".day-nav a[rel=next]", false
  end

  test "the arrows keep the filter and drop the page" do
    event(title: "FirstDayShow Late", start_date: @second + 1)

    get events_path(q: ["FirstDayShow"], day: @first.iso8601)

    assert_select ".day-nav a[rel=next][href=?]", events_path(q: ["FirstDayShow"], day: (@second + 1).iso8601)
  end

  test "a day without events redirects to the next day with events" do
    get events_path(day: (@first + 1).iso8601)

    assert_redirected_to events_path(day: @second.iso8601)
  end

  test "a day after the last one redirects to the last day" do
    get events_path(day: (@second + 30).iso8601)

    assert_redirected_to events_path(day: @second.iso8601)
  end

  test "a filter that no longer matches the linked day redirects within the filter" do
    get events_path(q: ["SecondDayShow"], day: @first.iso8601)

    assert_redirected_to events_path(q: ["SecondDayShow"], day: @second.iso8601)
  end

  test "an unreadable day redirects to the day the feed opens on" do
    get events_path(day: "someday")

    assert_redirected_to events_path(day: @first.iso8601)
  end

  test "a page from before day paging redirects away" do
    get events_path(page: 2)

    assert_redirected_to events_path
  end

  test "without a date filter the feed starts today" do
    event(title: "PastShow", start_date: Date.current - 3)

    get events_path(day: (Date.current - 3).iso8601)

    assert_redirected_to events_path(day: @first.iso8601)
  end

  test "a custom range reaches into the past, and the arrows follow it" do
    past = Date.current - 3
    event(title: "PastShow", start_date: past)
    range = "#{(past - 1).iso8601} - #{@second.iso8601}"

    get events_path(d: [range], day: @first.iso8601)

    assert_response :success
    assert_select ".day-nav a[rel=prev][href=?]", events_path(d: [range], day: past.iso8601)
  end

  test "a custom range entirely in the past opens on its last day" do
    past = Date.current - 3
    event(title: "PastShow", start_date: past)
    event(title: "OlderShow", start_date: past - 2)

    get events_path(d: ["#{(past - 5).iso8601} - #{(past + 1).iso8601}"])

    assert_includes response.body, "PastShow"
    refute_includes response.body, "OlderShow"
  end

  test "the calendar enables exactly the days with matching events" do
    get events_path

    enabled = JSON.parse(css_select(".day-nav [data-range-calendar-enabled-value]").first["data-range-calendar-enabled-value"])
    assert_equal [@first.iso8601, @second.iso8601], enabled
  end

  test "the day never becomes part of the stored filter" do
    get events_path(q: ["Show"], day: @second.iso8601)

    assert_response :success
    assert_equal({ "q" => ["Show"] }, JSON.parse(cookies[EventsController::FILTER_COOKIE.to_s]))
  end

  test "without any events there is no day and no navigation" do
    Event.delete_all

    get events_path(day: @first.iso8601)
    assert_redirected_to events_path

    get events_path
    assert_select "p.events-empty"
    assert_select ".day-nav", false
  end
end
