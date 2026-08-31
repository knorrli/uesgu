require "db_test_helper"

class SavedEventsTest < ActionDispatch::IntegrationTest
  test "saved events require authentication" do
    get saved_events_path
    assert_redirected_to new_session_path
  end

  test "toggle saves then unsaves an event" do
    u = sign_in_as user
    e = event(start_date: Date.current + 3)

    assert_difference -> { u.event_saves.count }, 1 do
      post toggle_saved_events_path, params: { event_id: e.id }
    end
    assert_response :no_content

    assert_difference -> { u.event_saves.count }, -1 do
      post toggle_saved_events_path, params: { event_id: e.id }
    end
  end

  test "reminders endpoint toggles the day-of saved-show reminder" do
    u = sign_in_as user
    refute u.event_reminders?

    patch reminders_saved_events_path, params: { enabled: true }
    assert_response :no_content
    assert u.reload.event_reminders?

    patch reminders_saved_events_path, params: { enabled: false }
    refute u.reload.event_reminders?
  end

  test "the reminder toggle shows on the saved-shows page only once something is saved" do
    u = sign_in_as user
    get saved_events_path
    assert_select ".saved-reminder", false, "no reminder toggle before anything is saved"

    u.event_saves.create!(event: event(start_date: Date.current + 3))
    get saved_events_path
    assert_select ".saved-reminder input[type=checkbox]"
  end

  test "the saved-shows page points at the calendar subscription in Settings" do
    u = sign_in_as user
    get saved_events_path
    assert_select "a[href=?]", settings_path(anchor: "calendar-feed"), false,
                  "no calendar pointer before anything is saved"

    u.event_saves.create!(event: event(start_date: Date.current + 3))
    get saved_events_path
    assert_select "a[href=?]", settings_path(anchor: "calendar-feed")
  end

  test "index lists upcoming saved shows and hides past ones" do
    u = sign_in_as user
    upcoming = event(start_date: Date.current + 3, title: "Upcoming Save")
    past = event(start_date: Date.current - 3, title: "Past Save")
    u.event_saves.create!(event: upcoming)
    u.event_saves.create!(event: past)

    get saved_events_path
    assert_response :success
    assert_select ".event-title", text: /Upcoming Save/
    assert_select ".event-title", text: /Past Save/, count: 0
  end

  test "the events list shows a save button for a logged-in user" do
    sign_in_as user
    event(start_date: Date.current + 2)

    get events_path
    assert_select "button.event-save"
  end

  test "a shelf holding only past saves gets the nothing-coming-up state, not the empty one" do
    u = sign_in_as user(locale: "en")
    u.event_saves.create!(event: event(start_date: Date.current - 1, title: "Earlier This Month"))

    get saved_events_path
    assert_select ".event-title", text: /Earlier This Month/, count: 0
    assert_select "p.empty-state", text: I18n.t("saved_events.none_upcoming", locale: :en)
  end
end
