require 'db_test_helper'

# Locks the rule engine: due? scheduling (daily/weekly), matched_events for the
# "added" (created_at window + future floor) and "happening" (start_date preset)
# content types, the favorites OR filter, and fire!'s snapshot + cursor advance.
# Synthetic events/styles only (see taxonomy rule in db_test_helper).
class NotificationRuleTest < ActiveSupport::TestCase
  # A fixed wall-clock anchor in the app zone (Europe/Berlin).
  NOON = Time.zone.local(2030, 6, 3, 12, 0, 0).freeze # a Monday
  TODAY = NOON.to_date

  def at(hour, minute = 0, date: TODAY)
    Time.zone.local(date.year, date.month, date.day, hour, minute)
  end

  # --- due? ------------------------------------------------------------------

  test 'daily rule is due after its time and not before, once per day' do
    rule = user.notification_rules.create!(cadence: 'daily', time_of_day: 18 * 60, content_type: 'added', scope: 'all')

    rule.update_column(:last_fired_at, at(12))
    assert rule.due?(at(18, 30)), 'due after 18:00 when last fired earlier today'
    refute rule.due?(at(17, 0)), 'not due before today\'s 18:00 (prev slot is yesterday, already covered)'

    rule.update_column(:last_fired_at, at(18, 5))
    refute rule.due?(at(18, 30)), 'not due again the same evening'
  end

  test 'weekly rule fires on its weekday after its time' do
    rule = user.notification_rules.create!(cadence: 'weekly', weekday: TODAY.wday, time_of_day: 11 * 60,
                                           content_type: 'added', scope: 'all')
    rule.update_column(:last_fired_at, at(0))

    assert rule.due?(at(12)), 'due on its weekday past 11:00'
    refute rule.due?(at(10)), 'not due before 11:00 on its weekday'
  end

  test 'disabled rule is never due' do
    rule = user.notification_rules.create!(cadence: 'daily', time_of_day: 0, content_type: 'added', scope: 'all', enabled: false)
    rule.update_column(:last_fired_at, at(0))
    refute rule.due?(at(23, 59))
  end

  # --- matched_events: added -------------------------------------------------

  test 'added matches events created since last fire that are not in the past' do
    u = user
    fresh = event(created_at: at(13), start_date: TODAY + 5)
    stale = event(created_at: at(8),  start_date: TODAY + 5)   # created before the window floor
    past  = event(created_at: at(13), start_date: TODAY - 5)   # in window but already happened

    rule = u.notification_rules.create!(cadence: 'daily', content_type: 'added', scope: 'all', time_of_day: 18 * 60)
    rule.update_column(:last_fired_at, at(12))

    matched = rule.matched_events(at(18)).to_a
    assert_includes matched, fresh
    refute_includes matched, stale
    refute_includes matched, past
  end

  test 'favorites scope matches a favorite style OR location' do
    u = user
    u.style_list = ['rule-fav-style']
    u.save!

    hit  = event(created_at: at(13), start_date: TODAY + 3)
    hit.update!(style_list: ['rule-fav-style'])
    miss = event(created_at: at(13), start_date: TODAY + 3)
    miss.update!(style_list: ['rule-other-style'])

    rule = u.notification_rules.create!(cadence: 'daily', content_type: 'added', scope: 'favorites', time_of_day: 1)
    rule.update_column(:last_fired_at, at(12))

    matched = rule.matched_events(at(18)).to_a
    assert_includes matched, hit
    refute_includes matched, miss
  end

  # --- matched_events: happening ---------------------------------------------

  test 'happening matches by start_date in the preset window regardless of created_at' do
    u = user
    today_show = event(start_date: Date.current, created_at: 1.hour.ago)
    rule = u.notification_rules.create!(cadence: 'daily', content_type: 'happening', window: 'today',
                                        scope: 'all', time_of_day: 1)
    assert_includes rule.matched_events(Time.current).to_a, today_show
  end

  # --- fire! -----------------------------------------------------------------

  test 'fire! snapshots matched events, advances the cursor, and skips empties' do
    u = user
    show = event(created_at: at(13), start_date: TODAY + 5)
    rule = u.notification_rules.create!(cadence: 'daily', content_type: 'added', scope: 'all', time_of_day: 18 * 60)
    rule.update_column(:last_fired_at, at(12))

    note = rule.fire!(at(18))
    assert_equal [show.id], note.event_ids
    assert_equal [show], note.events.to_a
    assert_equal at(18).to_i, rule.reload.last_fired_at.to_i

    # Nothing new after the cursor -> no notification.
    assert_nil rule.fire!(at(18, 1))
  end

  test 'run_due! fires due rules and ignores disabled ones' do
    u = user
    event(created_at: 1.hour.ago, start_date: Date.current + 3)

    # time_of_day 0 + last fired yesterday => reliably due whatever hour this runs.
    due = u.notification_rules.create!(cadence: 'daily', content_type: 'added', scope: 'all', time_of_day: 0, notify_push: false)
    due.update_column(:last_fired_at, 1.day.ago)
    off = u.notification_rules.create!(cadence: 'daily', content_type: 'added', scope: 'all', time_of_day: 0, enabled: false)
    off.update_column(:last_fired_at, 1.day.ago)

    created = NotificationRule.run_due!(Time.current)
    assert_equal 1, created.size
    assert_equal due.id, created.first.notification_rule_id
  end

  # --- validations -----------------------------------------------------------

  test 'happening content type requires a window' do
    rule = user.notification_rules.new(cadence: 'daily', content_type: 'happening', window: nil, scope: 'all')
    refute rule.valid?
    assert rule.errors[:window].any?
  end

  test 'weekly requires a weekday' do
    rule = user.notification_rules.new(cadence: 'weekly', weekday: nil, content_type: 'added', scope: 'all')
    refute rule.valid?
  end

  test 'time_string parses to minutes-since-midnight' do
    rule = NotificationRule.new
    rule.time_string = '17:30'
    assert_equal 1050, rule.time_of_day
    assert_equal '17:30', rule.time_string
  end
end
