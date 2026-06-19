require 'db_test_helper'

# Locks the reframed web flow: the landing "Notify me" button (filter-gated), the
# new-alert page (filter carried through + sync checkbox when it matches
# favorites), create from filter params, the no-empty-firehose guard, the
# read-only list, and fire/toggle/destroy. Email channel stays off.
class NotificationRulesTest < ActionDispatch::IntegrationTest
  # --- landing-page button ---------------------------------------------------

  test 'the save action shows only with an active filter' do
    sign_in_as user

    get events_path
    assert_select 'a.save-filter-link', false, 'no save on an empty filter'

    get events_path(g: ['Rock'])
    assert_select 'a.save-filter-link'
  end

  # --- new -------------------------------------------------------------------

  test 'new requires authentication' do
    get new_notification_rule_path
    assert_redirected_to new_session_path
  end

  test 'new (added filter) carries the filter through and wires the schedule form' do
    sign_in_as user
    leaf = genre_in_tree('Zylonew')
    get new_notification_rule_path(g: [leaf.name]) # no date → added rule

    assert_response :success
    # The picked genre is pre-checked in the What tree; window is a select.
    assert_select "input[name='g[]'][value='#{leaf.name}'][checked]"
    assert_select 'form[data-controller~="rule-form"]'
    assert_select 'select[name="notification_rule[cadence]"][data-rule-form-target="cadence"]'
    assert_select '[data-rule-form-target="weekday"]'
    # No name field — the name is the derived filter description, in the title.
    assert_select 'input[name="notification_rule[name]"]', false
    assert_select 'h1', text: /Zylonew/
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

  test 'the star lights when saved; the bell follows the notify state' do
    u = sign_in_as user

    # Unsaved: outline star (offers to save), no bell link yet.
    get events_path(g: ['Rock'])
    assert_select "a.save-filter-link[data-turbo-method='post']"
    assert_select 'a.save-filter-link.active', false
    assert_select 'a.notify-bell-link', false

    # A silent saved filter (notifications off): star lit, bell present but unlit.
    r = u.notification_rules.new(name: 'x', cadence: 'daily', time_of_day: 540, enabled: false)
    r.filter_attributes = { g: ['Rock'] }
    r.save!
    get events_path(g: ['Rock'])
    assert_select 'a.save-filter-link.active'
    assert_select "a.notify-bell-link[href=?]", notify_notification_rule_path(r)
    assert_select 'a.notify-bell-link.active', false

    # Notifying (enabled): both lit.
    r.update!(enabled: true)
    get events_path(g: ['Rock'])
    assert_select 'a.save-filter-link.active'
    assert_select 'a.notify-bell-link.active'
  end

  # --- save (★) / notify (🔔) lifecycle --------------------------------------

  test 'the star toggles a silent saved filter in place' do
    u = sign_in_as user

    assert_difference -> { u.notification_rules.count }, 1 do
      post toggle_save_notification_rules_path(g: ['Rock'])
    end
    r = u.notification_rules.last
    refute r.enabled?, 'a ★-saved filter is silent (notifications off)'
    assert_equal ['Rock'], r.genres

    # Toggling the same filter again removes it.
    assert_difference -> { u.notification_rules.count }, -1 do
      post toggle_save_notification_rules_path(g: ['Rock'])
    end
  end

  test 'the bell turns notifications on and opens the editor' do
    u = sign_in_as user
    r = u.notification_rules.new(name: 'x', cadence: 'daily', time_of_day: 540, enabled: false)
    r.filter_attributes = { g: ['Rock'] }
    r.save!

    post notify_notification_rule_path(r)
    assert r.reload.enabled?
    assert_redirected_to edit_notification_rule_path(r)
  end

  # --- edit / update ---------------------------------------------------------

  test 'edit shows the schedule + the saved filter pre-checked in the tree' do
    u = sign_in_as user
    leaf = genre_in_tree('Zyloedit')
    r = u.notification_rules.new(name: 'My alert', cadence: 'weekly', weekday: 5, time_of_day: 1050)
    r.filter_attributes = { g: [leaf.name] }
    r.save!

    get edit_notification_rule_path(r)
    assert_response :success
    # The saved genre is pre-checked in the What tree; the window is a <select>.
    assert_select "input[name='g[]'][value='#{leaf.name}'][checked]"
    assert_select 'select[name="d[]"]'
    # No name field; the derived name is the (server-rendered) page title.
    assert_select 'input[name="notification_rule[name]"]', false
    assert_select 'h1', text: /Zyloedit/
  end

  test 'update saves genre picks and free-text queries from the what field' do
    u = sign_in_as user
    r = u.notification_rules.new(cadence: 'daily', time_of_day: 60)
    r.filter_attributes = { g: ['Rock'] }
    r.save!

    # The What tree submits genre picks as g[] and free text as q[].
    patch notification_rule_path(r), params: {
      notification_rule: { cadence: 'daily', time_string: '09:00' },
      g: %w[Rock Jazz], q: ['Radiohead'], l: [''], d: ['']
    }

    assert_redirected_to notification_rules_path # explicit save returns to the list
    r.reload
    assert_equal %w[Rock Jazz], r.genres
    assert_equal ['Radiohead'], r.queries
  end

  test 'editing a filter to match another rule is allowed; the editor flags it' do
    u = sign_in_as user
    a = u.notification_rules.new(name: 'a', cadence: 'daily', time_of_day: 540)
    a.filter_attributes = { g: ['Rock'] }
    a.save!
    b = u.notification_rules.new(name: 'b', cadence: 'daily', time_of_day: 540)
    b.filter_attributes = { g: ['Jazz'] }
    b.save!

    # Editing B to match A IS applied (only the ★ dedupes); not blocked.
    patch notification_rule_path(b), params: { g: ['Rock'], l: [''], d: [''] }
    assert_redirected_to notification_rules_path
    assert_equal ['Rock'], b.reload.genres

    # The editor then surfaces a non-blocking notice linking to A.
    get edit_notification_rule_path(b)
    assert_select '.rule-notice a[href=?]', edit_notification_rule_path(a)
  end

  test 'editing only the schedule saves and returns to the list' do
    u = sign_in_as user
    r = u.notification_rules.new(name: 'r', cadence: 'daily', time_of_day: 540)
    r.filter_attributes = { g: ['Rock'] }
    r.save!

    patch notification_rule_path(r), params: {
      notification_rule: { cadence: 'daily', time_string: '20:00' }, g: ['Rock'], l: [''], d: ['']
    }

    assert_redirected_to notification_rules_path
    assert_equal 1200, r.reload.time_of_day
  end

  test 'update changes the schedule + channels without touching the filter' do
    u = sign_in_as user
    r = u.notification_rules.new(cadence: 'weekly', weekday: 5, time_of_day: 1050, notify_email: false)
    r.filter_attributes = { g: ['Rock'] }
    r.save!

    patch notification_rule_path(r), params: {
      notification_rule: { cadence: 'weekly', weekday: '2', time_string: '08:15', notify_push: '1', notify_email: '1' },
      g: ['Rock']
    }

    assert_redirected_to notification_rules_path
    r.reload
    assert_equal 2, r.weekday
    assert_equal 495, r.time_of_day
    assert r.notify_email?
    assert_equal ['Rock'], r.genres # filter untouched
  end

  test 'update with a windowed filter flips an added rule to happening' do
    u = sign_in_as user
    r = u.notification_rules.new(cadence: 'weekly', weekday: 5, time_of_day: 1050)
    r.filter_attributes = { g: ['Rock'] } # no date → added
    r.save!
    assert r.added?

    # Selecting a window in the form flips the rule to happening.
    patch notification_rule_path(r), params: {
      notification_rule: { cadence: 'weekly', weekday: '5', time_string: '17:30' },
      g: ['Rock'], d: ['this_weekend']
    }

    assert_redirected_to notification_rules_path
    r.reload
    assert_equal ['this_weekend'], r.date_ranges
    assert r.happening?
  end

  test "edit only reaches the current user's own rules" do
    other = User.create!(username: 'someone', password: 'password12345')
    foreign = other.notification_rules.new(cadence: 'daily', time_of_day: 60)
    foreign.filter_attributes = { g: ['Rock'] }
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

  private

  # A genre that actually renders in the editor's What tree: a root (no events) with
  # one in-use child, so genre_filter_tree includes it and the child is checkable.
  # Returns the child (the leaf you filter by).
  def genre_in_tree(name)
    root = genre(name: "#{name}root", events_count: 0)
    leaf = genre(name: name, events_count: 1)
    leaf.set_parent!(root)
    leaf
  end
end
