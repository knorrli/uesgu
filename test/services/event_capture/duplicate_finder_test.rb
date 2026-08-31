require "db_test_helper"

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

  test "a dismissed event is not offered" do
    listed(title: "Malevolence").dismiss!

    assert_empty find
  end

  test "an event already folded onto a canonical is not offered" do
    canonical = listed(title: "Malevolence")
    listed(title: "Malevolence").update!(canonical_event_id: canonical.id)

    assert_equal [canonical.id], find.map(&:id)
  end

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
