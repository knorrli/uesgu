require "db_test_helper"

# Locks the location type derivation. Locations have no stored type — venue vs
# region is derived from the VENUE REGISTRY (config/venues.yml via Venue): the
# placed, consumed venues (Venue.in_taxonomy) are the source of truth. Expectations
# are derived from the live registry, never hardcoded venue names, so this stays
# correct as the registry changes.
class LocationTest < ActiveSupport::TestCase
  setup do
    @venue = Venue.in_taxonomy.first # a placed, consumed venue
    skip "no venues in the taxonomy" if @venue.nil?
  end

  test "venue_names is the set of every placed consume venue's name" do
    assert_kind_of Set, Location.venue_names
    assert_includes Location.venue_names, @venue.name
  end

  test "a registry venue is classified as :venue" do
    assert Location.venue?(@venue.name)
    assert_equal :venue, Location.type_for(@venue.name)
  end

  test "an unknown place is classified as a region (:city), not a venue" do
    refute Location.venue?("Definitely Not A Venue 9000")
    assert_equal :city, Location.type_for("Definitely Not A Venue 9000")
  end

  test "a registry canton code is classified as :canton" do
    assert_equal :canton, Location.type_for(@venue.canton)
  end

  test "a registry city is classified as :city" do
    assert_equal :city, Location.type_for(@venue.city)
  end

  test "hierarchy groups each venue under its canton and city" do
    tree = Location.hierarchy

    assert_includes tree.keys, @venue.canton
    assert_includes tree[@venue.canton].keys, @venue.city
    assert_includes tree[@venue.canton][@venue.city], @venue.name
  end

  # A venue fed by an aggregator (no scraper covering its own domain) is approved
  # in the registry like any other and must fold into the taxonomy exactly the same
  # — classified as a venue and nested in the tree — otherwise the aggregator's
  # venues are unfilterable (the gap Bewegungsmelder first exposed).
  test "an aggregator-sourced venue folds into venue_names, type and tree" do
    agg = Venue.in_taxonomy.find(&:sourced_via_aggregator?)
    skip "no aggregator-sourced placed venue" if agg.nil?

    assert_includes Location.venue_names, agg.name
    assert_equal :venue, Location.type_for(agg.name)

    tree = Location.hierarchy
    assert_includes tree[agg.canton].keys, agg.city
    assert_includes tree[agg.canton][agg.city], agg.name
  end

  # A consume venue with no place (e.g. the Bewegungsmelder aggregator feed itself)
  # must be excluded from the tree — otherwise the favorites location picker calls
  # parameterize on a nil city and the whole /favorites page 500s.
  test "hierarchy excludes placeless venues and never yields a nil city/canton" do
    placeless = Venue.consuming.reject(&:placed?).first
    tree = Location.hierarchy

    refute_includes tree.keys, placeless.name if placeless
    assert_empty tree.keys.select(&:nil?), "no canton key may be nil"
    assert_empty tree.values.flat_map(&:keys).select(&:nil?), "no city key may be nil"
  end
end
