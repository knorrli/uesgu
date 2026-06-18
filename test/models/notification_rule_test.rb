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

  test 'a custom absolute date range is dropped on save (falls back to new events)' do
    r = rule(user, filter: { s: ['some-style'], d: ['2030-06-20 - 2030-06-25'] })
    assert_empty r.date_ranges, 'the absolute range is not stored as a window'
    assert r.added?
  end

  test 'a legacy stored custom range is ignored as a window (no dead past range)' do
    r = rule(user, filter: { s: ['some-style'] })
    # Simulate an old row that stored an absolute range directly in the jsonb.
    r.filter = r.filter.merge('date_ranges' => ['2020-01-01 - 2020-01-02'])
    assert_empty r.active_windows
    assert r.added?
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

  test 'the scheduled time tracks wall-clock across a DST spring-forward (no hour drift)' do
    # CET→CEST on Sun 2026-03-29: clocks jump 02:00→03:00. Adding 18h to local
    # midnight lands at 19:00 (the skipped hour double-counts); a daily 18:00 rule
    # must still resolve to 18:00 wall-clock.
    r = rule(user, filter: { s: ['x'] }, cadence: 'daily', time_of_day: 18 * 60)
    scheduled = r.previous_scheduled_at(Time.zone.local(2026, 3, 29, 20, 0))

    assert_equal [18, 0], [scheduled.hour, scheduled.min],
                 'daily 18:00 must fire at 18:00 CEST, not 19:00'
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
    # One event matching both styles, so the disabled rule *would* fire if enabled
    # — distinct filters keep the two rules legal under the one-per-filter rule.
    event(created_at: 1.hour.ago, start_date: Date.current + 3, style_list: ['probe-rock', 'probe-techno'])

    due = rule(u, filter: { s: ['probe-rock'] }, time_of_day: 0)
    due.save!
    due.update_column(:last_fired_at, 1.day.ago)
    off = rule(u, filter: { s: ['probe-techno'] }, time_of_day: 0, enabled: false)
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

  # --- dedupe (one rule per filter set) --------------------------------------

  test 'fingerprint is order-independent and ignores absolute date ranges' do
    a = rule(user, filter: { s: ['Rock', 'Jazz'], l: ['Bern'] })
    b = rule(user, filter: { l: ['Bern'], s: ['Jazz', 'Rock'] })
    assert_equal a.fingerprint, b.fingerprint

    # An absolute range isn't kept by a rule, so it doesn't affect identity.
    windowed = rule(user, filter: { s: ['Rock'], d: ['2030-01-01 - 2030-01-02'] })
    plain    = rule(user, filter: { s: ['Rock'] })
    assert_equal plain.fingerprint, windowed.fingerprint

    # A preset window *does* change identity.
    refute_equal plain.fingerprint, rule(user, filter: { s: ['Rock'], d: ['this_weekend'] }).fingerprint
  end

  test 'a second rule for the same filter set is invalid' do
    u = user
    rule(u, filter: { s: ['Rock'], l: ['Bern'] }).save!

    dup = rule(u, filter: { l: ['Bern'], s: ['Rock'] }) # order flipped, same set
    refute dup.valid?
    assert_includes dup.errors[:base], I18n.t('notification_rules.errors.duplicate')

    assert rule(u, filter: { s: ['Rock'] }).valid?, 'a different filter is fine'
  end

  test 'matching finds the rule for a filter, or nil' do
    u = user
    r = rule(u, filter: { s: ['Rock'] }).tap(&:save!)

    fp = NotificationRule.fingerprint_for(Filter.build(style_list: ['Rock']))
    assert_equal r, u.notification_rules.matching(fp)
    assert_nil u.notification_rules.matching(NotificationRule.fingerprint_for(Filter.build(style_list: ['Jazz'])))
  end

  # --- auto-naming -----------------------------------------------------------

  test 'describe auto-names from the filter, localized' do
    r = rule(user, filter: { s: ['Rock'], l: ['Dachstock'], d: ['this_weekend'] })
    assert_includes r.describe, 'Rock'
    assert_includes r.describe, 'Dachstock'
    I18n.with_locale(:en) { assert_includes r.describe, I18n.t('datepicker.this_weekend') }
  end

  test 'describe is <what> · [where] · <temporal>, with all-events and new-events fallbacks' do
    all = I18n.t('notification_rules.summary.scope_all')
    added = I18n.t('notification_rules.type.added')
    # no what → "Alle Events" leads; location-only still leads with it
    assert_equal "#{all} · Bern · #{added}", rule(user, filter: { l: ['Bern'] }).describe
    # added rule always ends with the new-events label
    assert_equal "Rock · #{added}", rule(user, filter: { s: ['Rock'] }).describe
    # happening rule ends with the window label
    assert_equal "Rock · Bern · #{I18n.t('datepicker.this_week')}",
                 rule(user, filter: { s: ['Rock'], l: ['Bern'], d: ['this_week'] }, weekday: 5).describe
  end

  test 'the name always mirrors the filter on save (no custom names)' do
    r = rule(user, filter: { l: ['Bern'], d: ['next_week'] }, weekday: 5) # next_week => weekly
    r.save!
    assert_equal r.describe, r.name

    # A name passed in is ignored — re-derived from the filter on save.
    given = rule(user, filter: { s: ['Rock'] }, name: 'Keep me')
    given.save!
    assert_equal given.describe, given.name
    refute_equal 'Keep me', given.name
  end

  test 'name re-derives when the filter changes' do
    r = rule(user, filter: { s: ['Rock'] }, weekday: 5) # weekday set for the weekly window below
    r.save!
    before = r.name

    r.filter_attributes = { l: ['Bern'], d: ['this_weekend'] }
    r.save!
    assert_equal r.describe, r.name
    refute_equal before, r.name
  end

  test 'describe for a live-favorites alert' do
    r = user.notification_rules.new(track_favorites: true, cadence: 'daily', time_of_day: 1)
    r.filter_attributes = {}
    # Favorites alert + the temporal suffix (no window → new events).
    assert_equal "#{I18n.t('notification_rules.favorites_live')} · #{I18n.t('notification_rules.type.added')}", r.describe
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

  # --- derive rhythm from window ---------------------------------------------

  test 'a happening rule cadence is derived from its window, ignoring any chosen cadence' do
    u = user
    weekend = rule(u, filter: { d: ['this_weekend'] }, cadence: 'daily', weekday: 5)
    weekend.save!
    assert_equal 'weekly', weekend.cadence # the daily choice is overridden

    month = rule(u, filter: { d: ['this_month'] }, cadence: 'daily', monthday: 1)
    month.save!
    assert_equal 'monthly', month.cadence

    today = rule(u, filter: { d: ['today'] }, cadence: 'weekly', weekday: 5)
    today.save!
    assert_equal 'daily', today.cadence
  end

  test 'window_rhythm reflects the window; nil for added rules' do
    assert_equal 'weekly', rule(user, filter: { d: ['this_weekend'] }).window_rhythm
    assert_equal 'monthly', rule(user, filter: { d: ['next_month'] }).window_rhythm
    assert_nil rule(user, filter: { s: ['Rock'] }).window_rhythm
  end

  # --- firehose guard --------------------------------------------------------

  test 'track_favorites with no favorites matches nothing (no firehose)' do
    u = user # follows nothing
    event(created_at: 1.hour.ago, start_date: Date.current + 3)
    r = u.notification_rules.new(track_favorites: true, cadence: 'daily', time_of_day: 1, notify_push: false)
    r.filter_attributes = {}
    r.save!
    r.update_column(:last_fired_at, 2.hours.ago)

    assert_empty r.matched_events(Time.current).to_a
  end

  test 'time_string parses to minutes-since-midnight' do
    r = NotificationRule.new
    r.time_string = '17:30'
    assert_equal 1050, r.time_of_day
    assert_equal '17:30', r.time_string
  end

  test 'time snaps to the quarter hour on save (the scheduler runs quarterly)' do
    r = rule(user, filter: { s: ['Rock'] })
    r.time_string = '17:03'
    r.save!
    assert_equal((17 * 60), r.time_of_day) # 17:03 → 17:00

    r.time_string = '17:08'
    r.save!
    assert_equal((17 * 60) + 15, r.time_of_day) # 17:08 → 17:15
  end
end
