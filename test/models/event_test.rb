require "db_test_helper"

# Locks Event's non-taxonomy mechanics: presence validations, the visible /
# cancelled scopes, cancellation predicate, venue extraction from the flat
# location tags, and the to_s summary. Visibility derivation (the music gate) is
# covered by genre_disposition_test.
class EventTest < ActiveSupport::TestCase
  test "title, start_date and url are required" do
    e = Event.new
    refute e.valid?
    assert_predicate e.errors[:title], :any?
    assert_predicate e.errors[:start_date], :any?
    assert_predicate e.errors[:url], :any?
  end

  test "visible scope excludes hidden events" do
    shown = event(hidden: false)
    event(hidden: true)
    assert_includes Event.visible, shown
    assert_equal 1, Event.visible.count
  end

  test "cancelled scope and predicate track cancelled_at" do
    live = event(cancelled_at: nil)
    called_off = event(cancelled_at: Time.current)

    assert called_off.cancelled?
    refute live.cancelled?
    assert_equal [called_off.id], Event.cancelled.map(&:id)
  end

  test "visible scope excludes dismissed events (even when not hidden)" do
    shown = event(hidden: false)
    gone = event(hidden: false)
    gone.dismiss!

    assert_includes Event.visible, shown
    refute_includes Event.visible, gone
    assert_equal [gone.id], Event.dismissed.map(&:id)
    assert_equal [shown.id], Event.kept.map(&:id)
  end

  test "dismiss! is sticky and idempotent" do
    e = event
    refute e.dismissed?

    e.dismiss!
    assert e.dismissed?
    first_stamp = e.dismissed_at

    e.dismiss!
    assert_equal first_stamp, e.reload.dismissed_at
  end

  test "venue picks the venue tag out of the flat location list" do
    venue_name = Location.venue_names.first
    skip "no scrapers registered" if venue_name.nil?
    e = event(location_list: [venue_name, "Some City", "BE"])

    assert_equal venue_name, e.venue.name
  end

  test "venue is nil when no location tag is a known venue" do
    e = event(location_list: %w[Nowheresville ZZ])
    assert_nil e.venue
  end

  test "to_s summarizes date, title and locations" do
    e = event(title: "A Very Long Concert Title That Exceeds The Limit For Sure",
              start_date: Date.new(2030, 5, 9), location_list: ["Some Venue"])
    summary = e.to_s

    assert_includes summary, "30-05-09"
    assert_includes summary, "Some Venue"
    assert_operator summary.length, :<, 200
  end

  test "lock_field! marks an overridable field, idempotently" do
    e = event
    refute e.overridden?(:title)

    e.lock_field!(:title)
    assert e.overridden?(:title)
    assert_equal %w[title], e.reload.overridden_fields

    e.lock_field!(:title)
    assert_equal %w[title], e.reload.overridden_fields
  end

  test "lock_field! ignores names outside OVERRIDABLE_FIELDS" do
    e = event
    e.lock_field!(:url)
    e.lock_field!(:hidden)
    assert_empty e.reload.overridden_fields
  end

  test "release_field! clears a locked field, idempotently" do
    e = event
    e.lock_field!(:description)
    assert e.overridden?(:description)

    e.release_field!(:description)
    refute e.reload.overridden?(:description)

    e.release_field!(:description) # no-op, no error
    assert_empty e.reload.overridden_fields
  end

  test "ransackable allowlists expose only the intended fields" do
    assert_equal %w[title description start_date].sort, Event.ransackable_attributes.sort
    assert_includes Event.ransackable_associations, "locations"
    assert_includes Event.ransackable_associations, "genres"
    refute_includes Event.ransackable_associations, "styles"
  end
end
