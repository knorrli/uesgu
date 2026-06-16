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

  # --- list / calendar toggle ------------------------------------------------

  test 'the view switcher only appears once something is saved' do
    u = sign_in_as user
    get saved_events_path
    assert_select 'nav.view-switcher', count: 0

    u.event_saves.create!(event: event(start_date: Date.current + 3))
    get saved_events_path
    assert_select 'nav.view-switcher'
  end

  test 'calendar view renders the month grid and persists the choice to the account' do
    u = sign_in_as user
    u.event_saves.create!(event: event(start_date: Date.current + 3))

    get saved_events_path(view: 'calendar')
    assert_response :success
    assert_select 'section.event-calendar'
    assert_equal 'calendar', u.reload.saved_events_view
  end

  test 'calendar day expansion lists that day saved shows, read-only' do
    u = sign_in_as user
    today_show = event(start_date: Date.current, title: 'Tonight Save')
    u.event_saves.create!(event: today_show)

    get saved_events_path(view: 'calendar', day: Date.current.iso8601)
    assert_response :success
    assert_select 'section.day-detail .event-title', text: /Tonight Save/
    # Read-only: tags are plain, not follow toggles.
    assert_select 'section.day-detail button.event-tag.fav', count: 0
  end

  test 'list view hides past saves but the calendar still holds them' do
    u = sign_in_as user
    # Yesterday is always strictly past (list hides it) yet always inside the
    # month window the calendar loads (beginning_of_month - 7 …).
    past_show = event(start_date: Date.current - 1, title: 'Earlier This Month')
    u.event_saves.create!(event: past_show)

    get saved_events_path # list
    assert_select '.event-title', text: /Earlier This Month/, count: 0
    assert_select 'p.empty-state' # has saves, none upcoming

    get saved_events_path(view: 'calendar')
    assert_select 'section.event-calendar .day-count'
    # Every show here is saved by definition, so the bookmark marker is suppressed
    # — it would otherwise flag every day and carry no signal.
    assert_select '.day-saved-marker', count: 0
  end
end
