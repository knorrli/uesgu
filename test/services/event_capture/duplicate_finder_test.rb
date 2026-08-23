require "db_test_helper"

# What the capture card offers a contributor as "is it one of these?". A proposal, so
# the net is wider than the sweep's — it reaches across venues within a town — and the
# question is which rows are worth putting in front of someone, not which may be
# folded unattended. Synthetic venue and town names throughout.
class EventCapture::DuplicateFinderTest < ActiveSupport::TestCase
  DATE = Date.current + 20

  def listed(title:, date: DATE, venue: "Zorpsaal", locality: "Zorpwil", **attrs)
    event(title: title, start_date: date, location_list: [venue, locality, "BE"].compact, **attrs)
  end

  def find(title: "Malevolence", date: DATE, place: "Zorpsaal", locality: "Zorpwil")
    EventCapture::DuplicateFinder.for(title: title, date: date, place: place, locality: locality)
  end

  test "finds the same show at the same venue on the same day" do
    listed(title: "Malevolence")

    assert_equal ["Malevolence"], find.map(&:title)
  end

  test "matches a title one source spells longer than the other" do
    listed(title: "Malevolence (UK) + support")

    assert_equal 1, find.size
  end

  test "an unrelated show at the same venue on the same day is not offered" do
    listed(title: "Zorpwil Blaskapelle Jahreskonzert")

    assert_empty find
  end

  # The case the nightly sweep structurally cannot reach: a show captured for a venue
  # the registry does not cover has no venue name to meet the other copy on, so the
  # town is the only thing the two share.
  test "matches on the town alone when the venues differ" do
    listed(title: "Malevolence", venue: "Andere Zorphalle")

    assert_equal 1, find.size
  end

  test "another day is another show" do
    listed(title: "Malevolence", date: DATE + 1)

    assert_empty find
  end

  test "a different town is not offered, however alike the title" do
    listed(title: "Malevolence", venue: "Zorphalle", locality: "Anderswil")

    assert_empty find
  end

  # An admin threw these away; offering to enrich one would walk that back.
  test "a dismissed event is not offered" do
    listed(title: "Malevolence").dismiss!

    assert_empty find
  end

  # Merging onto a duplicate would build a chain no listing follows.
  test "an event already folded onto a canonical is not offered" do
    canonical = listed(title: "Malevolence")
    listed(title: "Malevolence").update!(canonical_event_id: canonical.id)

    assert_equal [canonical.id], find.map(&:id)
  end

  # The music gate hid it for carrying only non-music genres — which is exactly what a
  # captured genre can legitimately lift, and it is the same show either way.
  test "a hidden event is still offered" do
    listed(title: "Malevolence", hidden: true)

    assert_equal 1, find.size
  end

  test "offers no more than it can show" do
    (EventCapture::DuplicateFinder::LIMIT + 2).times { listed(title: "Malevolence") }

    assert_equal EventCapture::DuplicateFinder::LIMIT, find.size
  end

  test "a candidate with no title or no date asks nothing" do
    listed(title: "Malevolence")

    assert_empty find(title: "  ")
    assert_empty find(date: nil)
  end
end
