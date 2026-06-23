require "db_test_helper"

class EventSaveTest < ActiveSupport::TestCase
  test "a user cannot save the same event twice" do
    u = user
    e = event
    u.event_saves.create!(event: e)

    dup = u.event_saves.build(event: e)
    refute dup.valid?
    assert dup.errors[:event_id].any?
  end

  test "saved_events returns the bookmarked events" do
    u = user
    e1 = event
    e2 = event
    u.event_saves.create!(event: e1)

    assert_includes u.saved_events, e1
    refute_includes u.saved_events, e2
  end
end
