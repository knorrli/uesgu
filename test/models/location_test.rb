require "db_test_helper"

class LocationTest < ActiveSupport::TestCase
  setup do
    @venue = Venue.in_taxonomy.first
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

  test "an aggregator-sourced venue folds into venue_names, type and tree" do
    agg = Venue.in_taxonomy.find(&:sourced_via_aggregator?)
    skip "no aggregator-sourced placed venue" if agg.nil?

    assert_includes Location.venue_names, agg.name
    assert_equal :venue, Location.type_for(agg.name)

    tree = Location.hierarchy
    assert_includes tree[agg.canton].keys, agg.locality
    assert_includes tree[agg.canton][agg.locality], agg.name
  end

  test "a captured place is classified as :venue, like a registry venue" do
    zorpsaal = place(name: "Zorpsaal")

    assert Location.venue?(zorpsaal.name)
    assert_equal :venue, Location.type_for(zorpsaal.name)
    assert_includes Location.venue_names, zorpsaal.name
  end

  test "hierarchy nests a captured place under its canton and locality" do
    zorpsaal = place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    tree = Location.hierarchy

    assert_includes tree["BE"].keys, "Zorpwil"
    assert_includes tree["BE"]["Zorpwil"], zorpsaal.name
  end

  test "captured places extend the registry tree rather than replacing it" do
    place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    tree = Location.hierarchy

    assert_includes tree[@venue.canton][@venue.locality], @venue.name
  end

  test "taxonomy_venue_fingerprints covers the registry only, never a place" do
    zorpsaal = place(name: "Zorpsaal")
    fingerprints = Location.taxonomy_venue_fingerprints

    assert_includes fingerprints, Fingerprint.for(@venue.name)
    refute_includes fingerprints, zorpsaal.fingerprint
  end

  test "hierarchy excludes placeless venues and never yields a nil locality/canton" do
    placeless = Venue.consuming.reject(&:placed?).first
    tree = Location.hierarchy

    refute_includes tree.keys, placeless.name if placeless
    assert_empty tree.keys.select(&:nil?), "no canton key may be nil"
    assert_empty tree.values.flat_map(&:keys).select(&:nil?), "no locality key may be nil"
  end
end
