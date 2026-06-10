require 'db_test_helper'

# Locks Event's non-taxonomy mechanics: presence validations, the visible /
# cancelled scopes, cancellation predicate, venue extraction from the flat
# location tags, and the to_s summary. Style derivation lives in
# event_styles_test.rb.
class EventTest < ActiveSupport::TestCase
  test 'title, start_date and url are required' do
    e = Event.new
    refute e.valid?
    assert_predicate e.errors[:title], :any?
    assert_predicate e.errors[:start_date], :any?
    assert_predicate e.errors[:url], :any?
  end

  test 'visible scope excludes hidden events' do
    shown = event(hidden: false)
    event(hidden: true)
    assert_includes Event.visible, shown
    assert_equal 1, Event.visible.count
  end

  test 'cancelled scope and predicate track cancelled_at' do
    live = event(cancelled_at: nil)
    called_off = event(cancelled_at: Time.current)

    assert called_off.cancelled?
    refute live.cancelled?
    assert_equal [called_off.id], Event.cancelled.map(&:id)
  end

  test 'venue picks the venue tag out of the flat location list' do
    venue_name = Location.venue_names.first
    skip 'no scrapers registered' if venue_name.nil?
    e = event(location_list: [venue_name, 'Some City', 'BE'])

    assert_equal venue_name, e.venue.name
  end

  test 'venue is nil when no location tag is a known venue' do
    e = event(location_list: %w[Nowheresville ZZ])
    assert_nil e.venue
  end

  test 'to_s summarizes date, title and locations' do
    e = event(title: 'A Very Long Concert Title That Exceeds The Limit For Sure',
              start_date: Date.new(2030, 5, 9), location_list: ['Some Venue'])
    summary = e.to_s

    assert_includes summary, '30-05-09'
    assert_includes summary, 'Some Venue'
    assert_operator summary.length, :<, 200
  end

  test 'ransackable allowlists expose only the intended fields' do
    assert_equal %w[title subtitle start_date].sort, Event.ransackable_attributes.sort
    assert_includes Event.ransackable_associations, 'locations'
    assert_includes Event.ransackable_associations, 'styles'
  end
end
