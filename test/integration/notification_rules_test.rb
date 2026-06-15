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

  test 'new (added filter) carries the filter through and wires the schedule form' do
    sign_in_as user
    get new_notification_rule_path(s: ['Rock'], l: ['Dachstock']) # no date → added rule

    assert_response :success
    # Filter pre-filled inline (combobox hidden fields), window as a select.
    assert_select 'input[name="s[]"][value=?]', 'Rock'
    assert_select 'input[name="l[]"][value=?]', 'Dachstock'
    assert_select 'form[data-controller="rule-form"]'
    assert_select 'select[name="notification_rule[cadence]"][data-rule-form-target="cadence"]'
    assert_select '[data-rule-form-target="weekday"]'
    # No name field — the name is derived; shown as a live preview in the title.
    assert_select 'input[name="notification_rule[name]"]', false
    assert_select '[data-rule-name-target="preview"]', text: /Dachstock/
  end

  test 'new (windowed filter) preselects the window and shows the firing-day picker' do
    sign_in_as user
    get new_notification_rule_path(l: ['Bern'], d: ['this_weekend']) # weekly window

    assert_response :success
    assert_select "select[name='d[]'] option[value='this_weekend'][selected='selected']"
    # The cadence picker is always in the DOM (hidden client-side when windowed);
    # the firing-day picker is present for the weekly rhythm.
    assert_select 'select[name="notification_rule[weekday]"]'
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

  # --- edit / update ---------------------------------------------------------

  test 'edit shows the rule schedule + its saved filter inline' do
    u = sign_in_as user
    r = u.notification_rules.new(name: 'My alert', cadence: 'weekly', weekday: 5, time_of_day: 1050)
    r.filter_attributes = { l: ['Dachstock'], s: ['Rock'] }
    r.save!

    get edit_notification_rule_path(r)
    assert_response :success
    # Filter pre-filled inline: the multiselect combobox hidden field carries the
    # current values, the window is a <select>.
    assert_select 'input[name="s[]"][value=?]', 'Rock'
    assert_select 'input[name="l[]"][value=?]', 'Dachstock'
    assert_select 'select[name="d[]"]'
    # No name field; the derived name shows as a live preview in the title.
    assert_select 'input[name="notification_rule[name]"]', false
    assert_select '[data-rule-name-target="preview"]', text: /Rock/
  end

  test 'update saves picked styles and free-text queries from the what field separately' do
    u = sign_in_as user
    r = u.notification_rules.new(cadence: 'daily', time_of_day: 60)
    r.filter_attributes = { s: ['Rock'] }
    r.save!

    # The "what" tag-picker submits styles as s[] and free text as q[].
    patch notification_rule_path(r), params: {
      notification_rule: { cadence: 'daily', time_string: '09:00' },
      s: %w[Rock Jazz], q: ['Radiohead'], l: [''], d: ['']
    }

    assert_redirected_to notification_rules_path
    r.reload
    assert_equal %w[Rock Jazz], r.style_list
    assert_equal ['Radiohead'], r.queries
  end

  test 'update changes the schedule + channels without touching the filter' do
    u = sign_in_as user
    r = u.notification_rules.new(cadence: 'weekly', weekday: 5, time_of_day: 1050, notify_email: false)
    r.filter_attributes = { s: ['Rock'] }
    r.save!

    patch notification_rule_path(r), params: {
      notification_rule: { cadence: 'weekly', weekday: '2', time_string: '08:15', notify_push: '1', notify_email: '1' },
      s: ['Rock']
    }

    assert_redirected_to notification_rules_path
    r.reload
    assert_equal 2, r.weekday
    assert_equal 495, r.time_of_day
    assert r.notify_email?
    assert_equal ['Rock'], r.style_list # filter untouched
  end

  test 'update with a windowed filter flips an added rule to happening' do
    u = sign_in_as user
    r = u.notification_rules.new(cadence: 'weekly', weekday: 5, time_of_day: 1050)
    r.filter_attributes = { s: ['Rock'] } # no date → added
    r.save!
    assert r.added?

    # Selecting a window in the inline form flips the rule to happening.
    patch notification_rule_path(r), params: {
      notification_rule: { cadence: 'weekly', weekday: '5', time_string: '17:30' },
      s: ['Rock'], d: ['this_weekend']
    }

    assert_redirected_to notification_rules_path
    r.reload
    assert_equal ['this_weekend'], r.date_ranges
    assert r.happening?
  end

  test "edit only reaches the current user's own rules" do
    other = User.create!(username: 'someone', password: 'password12345')
    foreign = other.notification_rules.new(cadence: 'daily', time_of_day: 60)
    foreign.filter_attributes = { s: ['Rock'] }
    foreign.save!

    sign_in_as user
    get edit_notification_rule_path(foreign)
    assert_response :not_found
  end

  # --- list + management -----------------------------------------------------

  test 'index lists alerts read-only with their summary and actions' do
    u = sign_in_as user
    r = u.notification_rules.new(cadence: 'weekly', weekday: 5, time_of_day: 1050)
    r.filter_attributes = { l: ['Dachstock'], d: ['this_weekend'] }
    r.save!

    get notification_rules_path
    assert_response :success
    # The name is the derived filter description (no custom names).
    assert_select '.rule-card .rule-card__name', /Dachstock/
    assert_select '.rule-card__actions form' # fire/toggle/delete
    assert_select ".rule-card__actions a[href=?]", edit_notification_rule_path(r), text: I18n.t('notification_rules.edit_button')
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
