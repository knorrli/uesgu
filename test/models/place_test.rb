require "db_test_helper"

# The captured-place vocabulary: the complement of the venue registry. Locks the
# invariants Location and the capture flow lean on — fingerprint matching, the
# NOT NULL place tuple, and the "never duplicate a registry venue" rule.
# Synthetic place names throughout; the registry is read live, never hardcoded.
class PlaceTest < ActiveSupport::TestCase
  test "a place carries a name, locality and canton" do
    zorpsaal = place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")

    assert_equal "Zorpsaal", zorpsaal.to_s
    assert_equal %w[Zorpwil BE], [zorpsaal.locality, zorpsaal.canton]
  end

  test "locality and canton are required — a place exists only to be a location" do
    assert_predicate Place.new(name: "Zorpsaal", canton: "BE"), :invalid?
    assert_predicate Place.new(name: "Zorpsaal", locality: "Zorpwil"), :invalid?
  end

  test "canton must be one of the 26, not free text" do
    refute Place.new(name: "Zorpsaal", locality: "Zorpwil", canton: "XX").valid?
    assert Place.new(name: "Zorpsaal", locality: "Zorpwil", canton: "VS").valid?
  end

  # The stored generated column and the Ruby reproduction are two copies of one
  # rule; a capture matches raw extracted text (no row yet) against rows written
  # by the DB, so a drift between them silently splits a place in two.
  test "the stored fingerprint reproduces Place.fingerprint_for exactly" do
    zorpsaal = place(name: "Zörp-Saal & Bar")

    assert_equal Place.fingerprint_for("Zörp-Saal & Bar"), zorpsaal.fingerprint
    assert_equal "zorpsaalandbar", zorpsaal.fingerprint
  end

  test "spelling variants of one name cannot become two places" do
    place(name: "Zorpsaal")

    refute Place.new(name: "ZORP SAAL", locality: "Zorpwil", canton: "BE").valid?
  end

  # The duplicate check is check-then-create, so two concurrent captures can both
  # pass it. The index is what actually holds the line.
  test "the unique index backstops the duplicate validation" do
    place(name: "Zorpsaal")
    duplicate = Place.new(name: "ZORP SAAL", locality: "Zorpwil", canton: "BE")

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "matching resolves a variant spelling to the stored place" do
    zorpsaal = place(name: "Zorpsaal")

    assert_equal zorpsaal, Place.matching("zorp-saal")
    assert_nil Place.matching("Flarnhalle")
  end

  test "matching follows a merge to the canonical place" do
    canonical = place(name: "Quartierfest Zorpwil")
    misspelt = place(name: "Quarterfest Zorpwil", canonical: canonical)

    assert_equal canonical, Place.matching("quarterfest zorpwil")
    assert_equal [misspelt], canonical.aliases
  end

  test "a place cannot be its own canonical" do
    zorpsaal = place
    assert_raises(ActiveRecord::StatementInvalid) { zorpsaal.update_column(:canonical_id, zorpsaal.id) }
  end

  test "a place may not duplicate a registry venue, in any spelling" do
    venue = Venue.in_taxonomy.first
    skip "no venues in the taxonomy" if venue.nil?

    refute Place.new(name: venue.name, locality: venue.locality, canton: venue.canton).valid?
    refute Place.new(name: venue.name.upcase, locality: venue.locality, canton: venue.canton).valid?
  end

  # The complement is drawn at the taxonomy, not at the file: a venue we decided
  # not to scrape (or never placed) is still somewhere a captured show can happen,
  # and the docs' "rejecting a lead" flow depends on the two rows coexisting.
  test "a place may duplicate a registry venue we do not source from" do
    unsourced = Venue.all.find { |v| !Venue.in_taxonomy.include?(v) }
    skip "every registry venue is in the taxonomy" if unsourced.nil?

    assert Place.new(name: unsourced.name, locality: "Zorpwil", canton: "BE").valid?
  end

  # The reverse direction the validation can't catch: the registry gains a row for
  # a place we already captured. `bin/rails places:drift` reports these.
  test "shadowed lists the places the registry has since absorbed" do
    venue = Venue.in_taxonomy.first
    skip "no venues in the taxonomy" if venue.nil?

    graduated = Place.new(name: venue.name, locality: venue.locality, canton: venue.canton)
    graduated.save!(validate: false)
    place(name: "Zorpsaal")

    assert_equal [graduated], Place.shadowed
  end

  test "an event tagged with a captured place surfaces it as the event's venue" do
    zorpsaal = place(name: "Zorpsaal")
    captured = event(location_list: [zorpsaal.name, zorpsaal.locality, zorpsaal.canton])

    assert_equal zorpsaal.name, captured.venue.name
  end
end
