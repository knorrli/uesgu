require "db_test_helper"

# Locks the subscribable ICS feed: the public token-keyed endpoint (no session),
# minting / rotating / removing the link, auth on management, and the settings UI.
class CalendarFeedTest < ActionDispatch::IntegrationTest
  test "the public feed serves ICS for a valid token without a session" do
    u = user
    u.regenerate_calendar_feed_token!
    u.event_saves.create!(event: event(title: "Feed Show", start_date: Date.current + 3))

    get public_calendar_feed_path(u.calendar_feed_token, format: :ics)
    assert_response :success
    assert_equal "text/calendar", response.media_type
    assert_includes response.body, "BEGIN:VCALENDAR"
    assert_includes response.body, "Feed Show"
  end

  test "an unknown token 404s" do
    get public_calendar_feed_path("nope-not-a-real-token", format: :ics)
    assert_response :not_found
  end

  test "creating mints a token and removing clears it" do
    u = sign_in_as user
    assert_nil u.calendar_feed_token

    post calendar_feed_path
    assert_redirected_to settings_path
    assert u.reload.calendar_feed_token.present?

    delete calendar_feed_path
    assert_redirected_to settings_path
    assert_nil u.reload.calendar_feed_token
  end

  test "regenerating rotates the token so the old URL stops working" do
    u = sign_in_as user
    post calendar_feed_path
    first = u.reload.calendar_feed_token
    post calendar_feed_path
    refute_equal first, u.reload.calendar_feed_token

    get public_calendar_feed_path(first, format: :ics)
    assert_response :not_found
  end

  test "managing the feed requires authentication" do
    post calendar_feed_path
    assert_redirected_to new_session_path
  end

  test "settings offers a create button with no link, the URL once present" do
    u = sign_in_as user
    get settings_path
    assert_select "input[data-clipboard-target=?]", "source", count: 0

    u.regenerate_calendar_feed_token!
    get settings_path
    assert_select "input[data-clipboard-target=?]", "source"
    assert_select "input[value=?]", public_calendar_feed_url(u.calendar_feed_token, format: :ics)
  end
end
