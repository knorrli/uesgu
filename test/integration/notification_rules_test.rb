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
    assert_select 'form[data-controller~="rule-form"]'
    assert_select 'select[name="notification_rule[cadence]"][data-rule-form-target="cadence"]'
    assert_select '[data-rule-form-target="weekday"]'
    # No name field — the name is the derived filter description, in the title.
    assert_select 'input[name="notification_rule[name]"]', false
    assert_select 'h1', text: /Dachstock/
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

  test 'create saves the filter and lands on the live editor' do
    u = sign_in_as user

    assert_difference -> { u.notification_rules.count }, 1 do
      post notification_rules_path, params: {
        notification_rule: { name: 'Bern weekends', cadence: 'weekly', weekday: '5',
                             time_string: '17:30', notify_push: '1', notify_email: '0' },
        l: ['Bern'], d: ['this_weekend']
      }
    end

    r = u.notification_rules.last
    assert_redirected_to edit_notification_rule_path(r) # create-on-click → live editor
    assert_equal 1050, r.time_of_day
    assert_equal ['Bern'], r.location_list
    assert_equal ['this_weekend'], r.date_ranges
    assert r.happening?
  end

  test 'create from a click uses safe defaults — push/email off' do
    u = sign_in_as user

    # The "Benachrichtigen" button POSTs only the filter (no notification_rule
    # params); the rule is created on the in-app bell only.
    assert_difference -> { u.notification_rules.count }, 1 do
      post notification_rules_path, params: { s: ['Rock'] }
    end

    r = u.notification_rules.last
    assert_redirected_to edit_notification_rule_path(r)
    refute r.notify_push?
    refute r.notify_email?
    assert r.enabled?
  end

  test 'create rejects an empty firehose filter' do
    u = sign_in_as user
    assert_no_difference -> { u.notification_rules.count } do
      post notification_rules_path, params: { notification_rule: { cadence: 'daily', time_string: '09:00' } }
    end
    assert_redirected_to events_path # bounced back, nothing created
  end

  # --- one rule per filter set -----------------------------------------------

  test 'create on a filter that already has a rule lands on the existing one, no duplicate' do
    u = sign_in_as user
    existing = u.notification_rules.new(name: 'x', cadence: 'daily', time_of_day: 540)
    existing.filter_attributes = { s: ['Rock'], l: ['Bern'] }
    existing.save!

    # Same filter set, order flipped → still the same rule.
    assert_no_difference -> { u.notification_rules.count } do
      post notification_rules_path, params: { l: ['Bern'], s: ['Rock'] }
    end
    assert_redirected_to edit_notification_rule_path(existing)
  end

  test 'the bell lights up and links to the existing rule for that filter' do
    u = sign_in_as user
    r = u.notification_rules.new(name: 'x', cadence: 'daily', time_of_day: 540)
    r.filter_attributes = { s: ['Rock'] }
    r.save!

    get events_path(s: ['Rock'])
    # Lit: it links (GET) to the rule's editor rather than POSTing a new one.
    assert_select "a.notify-filter-link.active[href=?]", edit_notification_rule_path(r)
    assert_select "a.notify-filter-link[data-turbo-method='post']", false

    # A different filter is not lit — it offers to create.
    get events_path(s: ['Jazz'])
    assert_select 'a.notify-filter-link.active', false
    assert_select "a.notify-filter-link[data-turbo-method='post']"
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
    # No name field; the derived name is the (server-rendered) page title.
    assert_select 'input[name="notification_rule[name]"]', false
    assert_select 'h1', text: /Rock/
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

    assert_response :success # autosave re-renders the editor in place
    r.reload
    assert_equal %w[Rock Jazz], r.style_list
    assert_equal ['Radiohead'], r.queries
  end

  test 'editing a filter to match another rule is allowed, with a heads-up linking to it' do
    u = sign_in_as user
    a = u.notification_rules.new(name: 'a', cadence: 'daily', time_of_day: 540)
    a.filter_attributes = { s: ['Rock'] }
    a.save!
    b = u.notification_rules.new(name: 'b', cadence: 'daily', time_of_day: 540)
    b.filter_attributes = { s: ['Jazz'] }
    b.save!

    # Editing B to match A IS applied (only the bell dedupes); a non-blocking
    # notice links to A.
    patch notification_rule_path(b), params: { s: ['Rock'], l: [''], d: [''] }

    assert_response :success
    assert_equal ['Rock'], b.reload.style_list
    assert_select '.rule-notice a[href=?]', edit_notification_rule_path(a)
  end

  test 'trimming a filter through a colliding intermediate state is never blocked' do
    u = sign_in_as user
    a = u.notification_rules.new(name: 'a', cadence: 'daily', time_of_day: 540)
    a.filter_attributes = { s: ['Rock', 'Metal'] }
    a.save!
    b = u.notification_rules.new(name: 'b', cadence: 'daily', time_of_day: 540)
    b.filter_attributes = { s: ['Rock', 'Metal', 'Jazz'] }
    b.save!

    # Autosave fires one PATCH per chip removed. Removing Jazz lands on
    # {Rock, Metal} — momentarily == A — which must still save…
    patch notification_rule_path(b), params: { s: %w[Rock Metal], l: [''], d: [''] }
    assert_response :success
    assert_equal %w[Metal Rock], b.reload.style_list.sort

    # …then removing Metal lands on {Rock}, the intended destination.
    patch notification_rule_path(b), params: { s: ['Rock'], l: [''], d: [''] }
    assert_response :success
    assert_equal ['Rock'], b.reload.style_list
  end

  test 'editing only the schedule saves and shows no duplicate notice' do
    u = sign_in_as user
    r = u.notification_rules.new(name: 'r', cadence: 'daily', time_of_day: 540)
    r.filter_attributes = { s: ['Rock'] }
    r.save!

    patch notification_rule_path(r), params: {
      notification_rule: { cadence: 'daily', time_string: '20:00' }, s: ['Rock'], l: [''], d: ['']
    }

    assert_response :success
    assert_equal 1200, r.reload.time_of_day
    assert_select '.rule-notice', false # only itself matches its filter
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

    assert_response :success # autosave re-renders the editor in place
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

    assert_response :success # autosave re-renders the editor in place
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
