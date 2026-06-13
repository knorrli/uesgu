require 'db_test_helper'

# Locks "save this show": the toggle endpoint, the saved-shows list (upcoming
# only), and the per-event save button on the events list.
class SavedEventsTest < ActionDispatch::IntegrationTest
  test 'saved events require authentication' do
    get saved_events_path
    assert_redirected_to new_session_path
  end

  test 'toggle saves then unsaves an event' do
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

  test 'index lists upcoming saved shows and hides past ones' do
    u = sign_in_as user
    upcoming = event(start_date: Date.current + 3, title: 'Upcoming Save')
    past = event(start_date: Date.current - 3, title: 'Past Save')
    u.event_saves.create!(event: upcoming)
    u.event_saves.create!(event: past)

    get saved_events_path
    assert_response :success
    assert_select '.event-title', text: /Upcoming Save/
    assert_select '.event-title', text: /Past Save/, count: 0
  end

  test 'the events list shows a save button for a logged-in user' do
    sign_in_as user
    event(start_date: Date.current + 2)

    get events_path
    assert_select 'button.event-save'
  end
end
