require "db_test_helper"

# Locks the location type derivation. Locations have no stored type — venue vs
# region is derived from the VENUE REGISTRY (config/venues.yml via Venue): the
# placed, consumed venues (Venue.in_taxonomy) are the source of truth. Expectations
# are derived from the live registry, never hardcoded venue names, so this stays
# correct as the registry changes. The canton codes are the exception: a closed
# list of 26 that must NOT follow the registry.
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

  test "an unknown place is classified as a region (:locality), not a venue" do
    refute Location.venue?("Definitely Not A Venue 9000")
    assert_equal :locality, Location.type_for("Definitely Not A Venue 9000")
  end

  test "a registry canton code is classified as :canton" do
    assert_equal :canton, Location.type_for(@venue.canton)
  end

  # The bug this list replaced: canton_codes was Venue.in_taxonomy's cantons, so a
  # tag for a canton we do not source from fell through to :locality and rendered
  # with a locality icon and a "· Ort" suffix everywhere a location is shown.
  test "a canton we source no venue from is still classified as :canton" do
    uncovered = Location::CANTON_CODES - Location.taxonomy_venues.map(&:canton).to_set
    skip "the registry covers all 26 cantons" if uncovered.empty?

    uncovered.each do |code|
      assert_equal :canton, Location.type_for(code), "#{code} must type as a canton"
    end
  end

  test "canton_codes is the closed set of all 26 Swiss cantons" do
    assert_equal 26, Location.canton_codes.size
    assert Location.canton_codes.frozen?
  end

  # The codes and their display names are two lists in two places; if they drift, a
  # canton renders as a raw code (missing name) or a name is dead weight (missing
  # code). Locked against every locale, not just the default.
  test "every canton code has a display name in every locale, and vice versa" do
    I18n.available_locales.each do |locale|
      names = I18n.t("cantons", locale: locale).keys.map(&:to_s).to_set

      assert_equal Location.canton_codes, names, "cantons: in #{locale}.yml must match CANTON_CODES"
    end
  end

  test "a registry locality is classified as :locality" do
    assert_equal :locality, Location.type_for(@venue.locality)
  end

  test "hierarchy groups each venue under its canton and locality" do
    tree = Location.hierarchy

    assert_includes tree.keys, @venue.canton
    assert_includes tree[@venue.canton].keys, @venue.locality
    assert_includes tree[@venue.canton][@venue.locality], @venue.name
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
    assert_includes tree[agg.canton].keys, agg.locality
    assert_includes tree[agg.canton][agg.locality], agg.name
  end

  # A consume venue with no place (e.g. the Bewegungsmelder aggregator feed itself)
  # must be excluded from the tree — otherwise the favorites location picker calls
  # parameterize on a nil locality and the whole /favorites page 500s.
  test "hierarchy excludes placeless venues and never yields a nil locality/canton" do
    placeless = Venue.consuming.reject(&:placed?).first
    tree = Location.hierarchy

    refute_includes tree.keys, placeless.name if placeless
    assert_empty tree.keys.select(&:nil?), "no canton key may be nil"
    assert_empty tree.values.flat_map(&:keys).select(&:nil?), "no locality key may be nil"
  end
end
