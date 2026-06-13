require 'db_test_helper'

# Locks the reframed rule engine: a saved filter + schedule. Inference
# (date window => happening, none => added), matched_events for both, live
# favorites, due? scheduling, fire! snapshot, and the no-empty-firehose guard.
# Synthetic events/styles only (see taxonomy rule in db_test_helper).
class NotificationRuleTest < ActiveSupport::TestCase
  NOON = Time.zone.local(2030, 6, 3, 12, 0, 0).freeze # a Monday
  TODAY = NOON.to_date

  def at(hour, minute = 0, date: TODAY)
    Time.zone.local(date.year, date.month, date.day, hour, minute)
  end

  def rule(user, filter:, **attrs)
    r = user.notification_rules.new({ cadence: 'daily', time_of_day: 18 * 60,
                                      notify_push: false, notify_email: false }.merge(attrs))
    r.filter_attributes = filter
    r
  end

  # --- inference -------------------------------------------------------------

  test 'a relative date window infers happening; no date infers added' do
    u = user
    assert rule(u, filter: { d: ['this_week'] }).happening?
    assert rule(u, filter: { s: ['some-style'] }).added?
    assert rule(u, filter: { l: ['Some Venue'] }).added?
  end

  # --- matched_events: added -------------------------------------------------

  # Real-current dates here: the non-favorites path delegates to
  # Filter#ransack_query, whose future floor is the real Date.current.
  test 'added matches events created since last fire that are not in the past' do
    u = user
    fresh = event(created_at: 1.hour.ago,  start_date: Date.current + 5, style_list: ['probe-rock'])
    stale = event(created_at: 5.hours.ago, start_date: Date.current + 5, style_list: ['probe-rock'])
    past  = event(created_at: 1.hour.ago,  start_date: Date.current - 5, style_list: ['probe-rock'])

    r = rule(u, filter: { s: ['probe-rock'] })
    r.save!
    r.update_column(:last_fired_at, 2.hours.ago)

    matched = r.matched_events(Time.current).to_a
    assert_includes matched, fresh
    refute_includes matched, stale # created before the window floor
    refute_includes matched, past  # already happened
  end

  # --- matched_events: happening ---------------------------------------------

  test 'happening matches by start_date in the window regardless of created_at' do
    u = user
    today_show = event(start_date: Date.current, created_at: 1.hour.ago)
    r = rule(u, filter: { d: ['today'] }, cadence: 'daily', time_of_day: 1)
    assert_includes r.matched_events(Time.current).to_a, today_show
  end

  # --- live favorites --------------------------------------------------------

  test 'track_favorites resolves the user current favorites (OR) at match time' do
    u = user
    u.style_list = ['rule-fav-style']
    u.save!
    hit  = event(created_at: at(13), start_date: TODAY + 3, style_list: ['rule-fav-style'])
    miss = event(created_at: at(13), start_date: TODAY + 3, style_list: ['other-style'])

    r = u.notification_rules.new(cadence: 'daily', time_of_day: 1, track_favorites: true, notify_push: false)
    r.save!
    r.update_column(:last_fired_at, at(12))

    matched = r.matched_events(at(18)).to_a
    assert_includes matched, hit
    refute_includes matched, miss
  end

  # --- due? ------------------------------------------------------------------

  test 'daily rule is due after its time and not before' do
    r = rule(user, filter: { s: ['x'] }, cadence: 'daily', time_of_day: 18 * 60)
    r.last_fired_at = at(12)
    assert r.due?(at(18, 30))
    refute r.due?(at(17, 0))
    r.last_fired_at = at(18, 5)
    refute r.due?(at(18, 30))
  end

  test 'weekly rule fires on its weekday after its time' do
    r = rule(user, filter: { s: ['x'] }, cadence: 'weekly', weekday: TODAY.wday, time_of_day: 11 * 60)
    r.last_fired_at = at(0)
    assert r.due?(at(12))
    refute r.due?(at(10))
  end

  # --- fire! -----------------------------------------------------------------

  test 'fire! snapshots matched events, advances the cursor, and skips empties' do
    u = user
    show = event(created_at: at(13), start_date: TODAY + 5, style_list: ['probe-rock'])
    r = rule(u, filter: { s: ['probe-rock'] }, time_of_day: 18 * 60)
    r.save!
    r.update_column(:last_fired_at, at(12))

    note = r.fire!(at(18))
    assert_equal [show.id], note.event_ids
    assert_equal at(18).to_i, r.reload.last_fired_at.to_i
    assert_nil r.fire!(at(18, 1)) # nothing new after the cursor
  end

  test 'run_due! fires due rules and ignores disabled ones' do
    u = user
    event(created_at: 1.hour.ago, start_date: Date.current + 3, style_list: ['probe-rock'])

    due = rule(u, filter: { s: ['probe-rock'] }, time_of_day: 0)
    due.save!
    due.update_column(:last_fired_at, 1.day.ago)
    off = rule(u, filter: { s: ['probe-rock'] }, time_of_day: 0, enabled: false)
    off.save!
    off.update_column(:last_fired_at, 1.day.ago)

    created = NotificationRule.run_due!(Time.current)
    assert_equal 1, created.size
    assert_equal due.id, created.first.notification_rule_id
  end

  # --- validations -----------------------------------------------------------

  test 'an empty filter is rejected unless it tracks favorites' do
    refute rule(user, filter: {}).valid?, 'empty filter, no favorites => invalid'
    assert rule(user, filter: {}, track_favorites: true).valid?, 'favorites alert is valid'
    assert rule(user, filter: { s: ['x'] }).valid?, 'any filter is valid'
  end

  # --- auto-naming -----------------------------------------------------------

  test 'describe auto-names from the filter, localized' do
    r = rule(user, filter: { s: ['Rock'], l: ['Dachstock'], d: ['this_weekend'] })
    assert_includes r.describe, 'Rock'
    assert_includes r.describe, 'Dachstock'
    I18n.with_locale(:en) { assert_includes r.describe, I18n.t('datepicker.this_weekend') }
  end

  test 'name auto-fills from the filter on save when blank, and is kept when given' do
    auto = rule(user, filter: { l: ['Bern'], d: ['next_week'] })
    auto.save!
    assert auto.name.present?
    assert_equal auto.describe, auto.name

    given = rule(user, filter: { s: ['Rock'] }, name: 'Keep me')
    given.save!
    assert_equal 'Keep me', given.name
  end

  test 'display_name uses the name when set, else describe' do
    unnamed = rule(user, filter: { s: ['Rock'] })
    assert_equal unnamed.describe, unnamed.display_name
    named = rule(user, filter: { s: ['Rock'] }, name: 'Mein Ding')
    assert_equal 'Mein Ding', named.display_name
  end

  test 'describe for a live-favorites alert' do
    r = user.notification_rules.new(track_favorites: true, cadence: 'daily', time_of_day: 1)
    r.filter_attributes = {}
    assert_equal I18n.t('notification_rules.favorites_live'), r.describe
  end

  test 'a fired notification snapshots the auto-name as its title' do
    u = user
    event(created_at: 1.hour.ago, start_date: Date.current + 3, style_list: ['Rock'])
    r = rule(u, filter: { s: ['Rock'] }, time_of_day: 1)
    r.save!
    r.update_column(:last_fired_at, 2.hours.ago)
    note = r.fire!(Time.current)
    assert_equal r.describe, note.title
  end

  test 'time_string parses to minutes-since-midnight' do
    r = NotificationRule.new
    r.time_string = '17:30'
    assert_equal 1050, r.time_of_day
    assert_equal '17:30', r.time_string
  end
end
