require "db_test_helper"

# Locks the location type derivation. Locations have no stored type — venue vs
# region is derived from the registered scrapers (each declares
# [venue, *aliases, city, canton]). Expectations are derived from the live
# Scrapers::All registry, never hardcoded venue names, so this stays correct as
# the fleet changes.
class LocationTest < ActiveSupport::TestCase
  setup do
    # A single-venue scraper (skip aggregators like Petzi, whose class-level place
    # is a placeholder — see Location.place_scrapers).
    @scraper = Scrapers::All.scrapers.values.reject(&:aggregator?).first
    skip "no scrapers registered" if @scraper.nil?
  end

  test "venue_names is the set of every scrapers declared venue" do
    assert_kind_of Set, Location.venue_names
    assert_includes Location.venue_names, @scraper.location
  end

  test "a declared venue is classified as :venue" do
    assert Location.venue?(@scraper.location)
    assert_equal :venue, Location.type_for(@scraper.location)
  end

  test "an unknown place is classified as a region (:city), not a venue" do
    refute Location.venue?("Definitely Not A Venue 9000")
    assert_equal :city, Location.type_for("Definitely Not A Venue 9000")
  end

  test "a declared canton code is classified as :canton" do
    canton = @scraper.locations.last
    assert_equal :canton, Location.type_for(canton)
  end

  test "a declared city is classified as :city" do
    city = @scraper.locations[-2]
    assert_equal :city, Location.type_for(city)
  end

  test "hierarchy groups each venue under its canton and city" do
    locations = @scraper.locations
    canton = locations.last
    city = locations[-2]

    tree = Location.hierarchy

    assert_includes tree.keys, canton
    assert_includes tree[canton].keys, city
    assert_includes tree[canton][city], @scraper.location
  end

  # A per-event aggregator can't declare its venues in code, so it persists the
  # places it resolves (VenuePlace). Those must fold into the taxonomy exactly
  # like a declared scraper place — classified as a venue and nested in the tree —
  # otherwise the aggregator's venues are unfilterable (the gap Bewegungsmelder
  # first exposed). Synthetic names (project-test-synthetic-taxonomy).
  test "an aggregator-resolved VenuePlace folds into venue_names, type and tree" do
    VenuePlace.create!(venue: "Glorphalle", city: "Snarftown", canton: "BE",
                       source: "OLE:Test")

    assert_includes Location.venue_names, "Glorphalle"
    assert_equal :venue, Location.type_for("Glorphalle")

    tree = Location.hierarchy
    assert_includes tree["BE"].keys, "Snarftown"
    assert_includes tree["BE"]["Snarftown"], "Glorphalle"
  end

  # Regression: a multi-venue aggregator (Petzi) declares only a placeholder
  # [location] (size 1), so it has no city. It must be excluded from the tree —
  # otherwise the favorites location picker calls parameterize on a nil city and
  # the whole /favorites page 500s.
  test "hierarchy excludes aggregator scrapers and never yields a nil city" do
    tree = Location.hierarchy

    aggregators = Scrapers::All.scrapers.values.select(&:aggregator?)
    aggregators.each do |agg|
      refute_includes tree.keys, agg.location, "#{agg} should not appear as a canton"
    end

    cities = tree.values.flat_map(&:keys)
    assert_empty cities.select(&:nil?), "no city key may be nil"
  end
end
