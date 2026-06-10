require 'db_test_helper'

# Locks the Datepicker preset structure and date math. Labels are I18n strings
# (locale-dependent), so we assert their presence but never their text.
class DatepickerTest < ActiveSupport::TestCase
  test 'exposes every preset key with indifferent access' do
    preset = Datepicker.preset
    assert_equal %i[today tomorrow this_week this_weekend next_week next_weekend this_month next_month],
                 preset.keys.map(&:to_sym)
    assert_equal preset[:today], preset['today'], 'indifferent access'
  end

  test 'each preset carries a label and a two-element iso date range' do
    Datepicker.preset.each_value do |entry|
      assert entry[:label].present?
      assert_equal 2, entry[:values].size
      entry[:values].each { |v| assert_match(/\A\d{4}-\d{2}-\d{2}\z/, v) }
    end
  end

  test 'today and tomorrow resolve to the current dates' do
    preset = Datepicker.preset
    assert_equal [Date.current.iso8601, Date.current.iso8601], preset[:today][:values]
    assert_equal [Date.current.tomorrow.iso8601, Date.current.tomorrow.iso8601], preset[:tomorrow][:values]
  end

  test 'this_month spans the calendar month' do
    values = Datepicker.preset[:this_month][:values]
    assert_equal Date.current.beginning_of_month.iso8601, values.first
    assert_equal Date.current.end_of_month.iso8601, values.last
  end

  test 'preset is rebuilt per call (not memoized stale)' do
    refute_same Datepicker.preset, Datepicker.preset
  end
end
