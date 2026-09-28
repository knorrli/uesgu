require "db_test_helper"

class VenueFoldTest < ActiveSupport::TestCase
  ZORPHALLE = Venue.new("domain" => "zorphalle.ch", "name" => "Kulturhalle Zorphalle",
                        "former_names" => ["Zorphalle"],
                        "place" => { "locality" => "Zorpwil", "canton" => "BE" })

  def with_registry(&) = Location.stub(:taxonomy_venues, [ZORPHALLE], &)

  def saved_filter(owner, locations)
    rule = owner.saved_filters.new(cadence: "daily", time_of_day: 18 * 60)
    rule.filter_attributes = { l: locations }
    rule.save!
    rule
  end

  test "an event tagged with the venue's former name carries its current name" do
    show = event(location_list: %w[Zorphalle Zorpwil BE])

    with_registry { VenueFold.run! }

    assert_equal ["BE", "Kulturhalle Zorphalle", "Zorpwil"], show.reload.location_list.sort
  end

  test "a variant spelling of the current name folds into it" do
    show = event(location_list: ["KULTURHALLE ZORPHALLE", "Zorpwil", "BE"])

    with_registry { VenueFold.run! }

    assert_includes show.reload.location_list, "Kulturhalle Zorphalle"
    refute_includes show.location_list, "KULTURHALLE ZORPHALLE"
  end

  test "an unrelated venue is left alone" do
    show = event(location_list: %w[Flarnkeller Zorpwil BE])

    with_registry { VenueFold.run! }

    assert_equal %w[BE Flarnkeller Zorpwil], show.reload.location_list.sort
  end

  test "a saved filter naming the former name follows the rename" do
    rule = saved_filter(user, ["Zorphalle"])

    with_registry { VenueFold.run! }

    assert_equal ["Kulturhalle Zorphalle"], rule.reload.location_list
  end

  test "a saved filter the rename turns into a duplicate of another is dropped" do
    owner = user
    kept = saved_filter(owner, ["Kulturhalle Zorphalle"])
    dropped = saved_filter(owner, ["Zorphalle"])

    with_registry { VenueFold.run! }

    assert_predicate SavedFilter.where(id: dropped.id), :empty?
    assert_equal ["Kulturhalle Zorphalle"], kept.reload.location_list
  end

  test "a captured place the venue has taken over is deleted" do
    taken = place(name: "Kulturhalle Zorphalle", locality: "Zorpwil", canton: "BE")
    former = place(name: "Zorphalle", locality: "Zorpwil", canton: "BE")
    other = place(name: "Flarnkeller", locality: "Zorpwil", canton: "BE")

    with_registry { VenueFold.run! }

    assert_predicate Place.where(id: [taken.id, former.id]), :empty?
    assert Place.exists?(other.id)
  end

  test "folding twice changes nothing the second time" do
    show = event(location_list: %w[Zorphalle Zorpwil BE])

    with_registry do
      VenueFold.run!
      VenueFold.run!
    end

    assert_equal ["BE", "Kulturhalle Zorphalle", "Zorpwil"], show.reload.location_list.sort
  end
end
