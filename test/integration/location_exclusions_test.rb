require "db_test_helper"

class LocationExclusionsTest < ActionDispatch::IntegrationTest
  setup do
    @hall = place(name: "Exclusionhalle")
    @there = event(title: "ThereMarkerShow", location_list: [@hall.name, @hall.locality, @hall.canton])
    @elsewhere = event(title: "ElsewhereMarkerShow", location_list: [@hall.locality, @hall.canton])
  end

  test "signed out, the feed offers no exclude button for a venue" do
    get events_path

    assert_select "form[action=?]", location_exclusions_path, false
  end

  test "excluding requires an account" do
    post location_exclusions_path, params: { name: @hall.name }

    assert_redirected_to new_session_path
    assert_equal 0, LocationExclusion.count
  end

  test "the venue, its town and its canton each carry an exclude button" do
    sign_in_as user

    get events_path

    assert_select ".event-where form[action=?] input[name=name][value=?]", location_exclusions_path, @hall.name
    group = Nokogiri::HTML(response.body).at_css("##{dom_id(@there)}").ancestors(".venue-group").first
    assert_equal [@hall.locality, @hall.canton], group.css(".event-where-meta form input[name=name]").map { |input| input["value"] }
  end

  test "a notification's event list carries the exclude button" do
    listener = sign_in_as user
    digest = listener.notifications.create!(title: "D", event_ids: [@there.id],
                                            period_start: 2.days.ago, period_end: Time.current)

    get notification_path(digest)

    assert_response :success
    assert_select ".event-where form[action=?] input[name=name][value=?]", location_exclusions_path, @hall.name
  end

  test "the saved-shows list carries the exclude button" do
    listener = sign_in_as user
    listener.event_saves.create!(event: @there)

    get saved_events_path

    assert_response :success
    assert_select ".event-where form[action=?] input[name=name][value=?]", location_exclusions_path, @hall.name
  end

  test "a town heading without a venue carries an exclude button" do
    sign_in_as user

    get events_path

    assert_select ".event-where form[action=?] input[name=name][value=?]", location_exclusions_path, @hall.locality
  end

  test "excluding a town leaves out every event there, at a venue or not" do
    listener = sign_in_as user

    post location_exclusions_path, params: { name: @hall.locality }

    assert_equal [@hall.locality], listener.location_exclusions.pluck(:name)
    get events_path
    refute_includes response.body, "ThereMarkerShow"
    refute_includes response.body, "ElsewhereMarkerShow"
  end

  test "excluding a venue takes effect at once and returns to the page it was pressed on" do
    listener = sign_in_as user
    feed = events_path(l: [@hall.locality], filtered: 1)

    post location_exclusions_path, params: { name: @hall.name, return_to: feed }

    assert_redirected_to feed
    assert_equal [@hall.name], listener.location_exclusions.pluck(:name)
    get events_path
    assert_includes response.body, "ElsewhereMarkerShow"
    refute_includes response.body, "ThereMarkerShow"
  end

  test "excluding twice keeps one exclusion" do
    listener = sign_in_as user

    2.times { post location_exclusions_path, params: { name: @hall.name } }

    assert_equal 1, listener.location_exclusions.count
  end

  test "a name no event is located at is not found" do
    sign_in_as user

    post location_exclusions_path, params: { name: "Nosuchhalle" }

    assert_response :not_found
  end

  test "filtering for an excluded venue shows its events" do
    listener = sign_in_as user
    listener.location_exclusions.create!(name: @hall.name)

    get events_path(l: [@hall.name])

    assert_includes response.body, "ThereMarkerShow"
    assert_select ".day-summary__count--excluded", false
  end

  test "the feed counts events left out at an excluded venue" do
    listener = sign_in_as user(locale: "en")
    listener.location_exclusions.create!(name: @hall.name)

    get events_path

    assert_select ".day-summary__count--excluded[aria-label=?]", "1 event left out because of your exclusions.", text: "1"
  end

  test "the settings list excluded places, and removing one shows its events again" do
    listener = sign_in_as user
    exclusion = listener.location_exclusions.create!(name: @hall.name)

    get settings_path

    assert_select "#excluded-locations form[action=?]", location_exclusion_path(exclusion), count: 1

    delete location_exclusion_path(exclusion)

    assert_redirected_to settings_path(anchor: "excluded-locations")
    assert_empty listener.location_exclusions.reload
  end

  test "another user's exclusion cannot be removed" do
    exclusion = user.location_exclusions.create!(name: @hall.name)
    sign_in_as user

    delete location_exclusion_path(exclusion)

    assert_response :not_found
    assert LocationExclusion.exists?(exclusion.id)
  end
end
