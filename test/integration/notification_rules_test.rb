require 'db_test_helper'

# Locks the reframed web flow: the landing "Notify me" button (filter-gated), the
# new-alert page (filter carried through + sync checkbox when it matches
# favorites), create from filter params, the no-empty-firehose guard, the
# read-only list, and fire/toggle/destroy. Email channel stays off.
class NotificationRulesTest < ActionDispatch::IntegrationTest
  # --- landing-page button ---------------------------------------------------

  test 'the Notify-me button shows only with an active filter' do
    sign_in_as user

    get events_path
    assert_select 'a.notify-filter-link', false, 'no button on an empty filter'

    get events_path(s: ['Rock'])
    assert_select 'a.notify-filter-link'
  end

  # --- new -------------------------------------------------------------------

  test 'new requires authentication' do
    get new_notification_rule_path
    assert_redirected_to new_session_path
  end

  test 'new (added filter) carries the filter through and wires the cadence form' do
    sign_in_as user
    get new_notification_rule_path(s: ['Rock'], l: ['Dachstock']) # no date → added rule

    assert_response :success
    assert_select 'input[type=hidden][name="s[]"][value=?]', 'Rock'
    assert_select 'input[type=hidden][name="l[]"][value=?]', 'Dachstock'
    assert_select 'fieldset[data-controller="rule-form"]'
    assert_select 'select[name="notification_rule[cadence]"][data-rule-form-target="cadence"]'
    assert_select '[data-rule-form-target="weekday"]'
    # Name field is pre-filled with the auto-name (here: the Dachstock location).
    assert_select 'input[name="notification_rule[name]"][value*=?]', 'Dachstock'
  end

  test 'new (windowed filter) shows the derived-rhythm schedule, no cadence picker' do
    sign_in_as user
    get new_notification_rule_path(l: ['Bern'], d: ['this_weekend']) # weekly window

    assert_response :success
    assert_select 'input[type=hidden][name="d[]"][value=?]', 'this_weekend'
    assert_select 'select[name="notification_rule[cadence]"]', false # rhythm is derived
    assert_select 'select[name="notification_rule[weekday]"]'        # firing-day picker
  end

  test 'the sync checkbox appears only when the filter equals my favorites' do
    u = sign_in_as user
    u.style_list = ['Techno']
    u.save!

    get new_notification_rule_path(s: ['Techno'])
    assert_select 'input[name="notification_rule[track_favorites]"]'

    get new_notification_rule_path(s: ['Jazz'])
    assert_select 'input[name="notification_rule[track_favorites]"]', false
  end

  # --- create ----------------------------------------------------------------

  test 'create saves the filter + schedule and infers happening' do
    u = sign_in_as user

    assert_difference -> { u.notification_rules.count }, 1 do
      post notification_rules_path, params: {
        notification_rule: { name: 'Bern weekends', cadence: 'weekly', weekday: '5',
                             time_string: '17:30', notify_push: '1', notify_email: '0' },
        l: ['Bern'], d: ['this_weekend']
      }
    end

    assert_redirected_to notification_rules_path
    r = u.notification_rules.last
    assert_equal 1050, r.time_of_day
    assert_equal ['Bern'], r.location_list
    assert_equal ['this_weekend'], r.date_ranges
    assert r.happening?
  end

  test 'create rejects an empty firehose filter' do
    u = sign_in_as user
    assert_no_difference -> { u.notification_rules.count } do
      post notification_rules_path, params: { notification_rule: { cadence: 'daily', time_string: '09:00' } }
    end
    assert_response :unprocessable_entity
  end

  # --- list + management -----------------------------------------------------

  test 'index lists alerts read-only with their summary and actions' do
    u = sign_in_as user
    r = u.notification_rules.new(name: 'My alert', cadence: 'weekly', weekday: 5, time_of_day: 1050)
    r.filter_attributes = { l: ['Dachstock'], d: ['this_weekend'] }
    r.save!

    get notification_rules_path
    assert_response :success
    assert_select '.rule-card .rule-card__name', /My alert/
    assert_select '.rule-card__actions form' # fire/toggle/delete
    assert_select 'a', text: I18n.t('notification_rules.edit_filter')
  end

  test 'fire now creates an in-app notification when there are matches' do
    u = sign_in_as user
    event(created_at: 1.hour.ago, start_date: Date.current + 3, style_list: ['Rock'])
    r = u.notification_rules.new(cadence: 'daily', time_of_day: 1, notify_push: false, notify_email: false)
    r.filter_attributes = { s: ['Rock'] }
    r.save!
    r.update_column(:last_fired_at, 2.hours.ago)

    assert_difference -> { u.notifications.count }, 1 do
      post fire_notification_rule_path(r)
    end
    assert_redirected_to notification_path(u.notifications.last) # lands on the digest
  end

  test 'fire with no matches stays on the list with an empty notice' do
    u = sign_in_as user
    r = u.notification_rules.new(cadence: 'daily', time_of_day: 1, notify_push: false)
    r.filter_attributes = { s: ['nothing-matches-this'] }
    r.save!

    assert_no_difference -> { u.notifications.count } do
      post fire_notification_rule_path(r)
    end
    assert_redirected_to notification_rules_path
  end

  test 'toggle pauses and destroy removes' do
    u = sign_in_as user
    r = u.notification_rules.new(cadence: 'daily', time_of_day: 1)
    r.filter_attributes = { s: ['Rock'] }
    r.save!

    patch toggle_notification_rule_path(r)
    refute r.reload.enabled?

    assert_difference -> { u.notification_rules.count }, -1 do
      delete notification_rule_path(r)
    end
  end
end
