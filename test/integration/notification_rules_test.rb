require 'db_test_helper'

# Locks the web layer: auth gate, the index builder renders, and
# create/fire/toggle/destroy behave. Email channel stays off so nothing is sent.
class NotificationRulesTest < ActionDispatch::IntegrationTest
  test 'index requires authentication' do
    get notification_rules_path
    assert_redirected_to new_session_path
  end

  test 'index renders the rule list and the builder' do
    sign_in_as user
    get notification_rules_path

    assert_response :success
    assert_select 'form.rule-form'
    assert_select 'select[name="notification_rule[cadence]"]'
    assert_select 'select[name="notification_rule[content_type]"]'
    assert_select 'select[name="notification_rule[scope]"]'
  end

  test 'index renders an existing rule card with its summary and actions' do
    u = sign_in_as user
    u.notification_rules.create!(name: 'My alert', cadence: 'weekly', weekday: 5,
                                 content_type: 'happening', window: 'this_weekend',
                                 scope: 'favorites', time_of_day: 1050)
    get notification_rules_path

    assert_response :success
    assert_select '.rule-card .rule-card__name', text: 'My alert'
    assert_select '.rule-card__summary'            # rule_summary helper rendered
    assert_select '.rule-card__actions form'       # fire/toggle/delete buttons
  end

  test 'create persists a rule and parses the time' do
    u = sign_in_as user

    assert_difference -> { u.notification_rules.count }, 1 do
      post notification_rules_path, params: { notification_rule: {
        name: 'Bern weekends', cadence: 'weekly', weekday: '5', content_type: 'happening',
        window: 'this_weekend', scope: 'custom', filter_locations: 'Dachstock, Rössli',
        time_string: '17:30', notify_push: '1', notify_email: '0'
      } }
    end

    assert_redirected_to notification_rules_path
    rule = u.notification_rules.last
    assert_equal 1050, rule.time_of_day
    assert_equal 'happening', rule.content_type
    assert_equal %w[Dachstock Rössli], rule.filter['location_list']
  end

  test 'fire now creates an in-app notification when there are matches' do
    u = sign_in_as user
    event(created_at: 1.hour.ago, start_date: Date.current + 3)
    rule = u.notification_rules.create!(cadence: 'daily', content_type: 'added', scope: 'all',
                                        time_of_day: 1, notify_push: false, notify_email: false)
    rule.update_column(:last_fired_at, 2.hours.ago)

    assert_difference -> { u.notifications.count }, 1 do
      post fire_notification_rule_path(rule)
    end
    assert_redirected_to notification_rules_path
  end

  test 'toggle pauses and destroy removes' do
    u = sign_in_as user
    rule = u.notification_rules.create!(cadence: 'daily', content_type: 'added', scope: 'all')

    patch toggle_notification_rule_path(rule)
    refute rule.reload.enabled?

    assert_difference -> { u.notification_rules.count }, -1 do
      delete notification_rule_path(rule)
    end
  end
end
