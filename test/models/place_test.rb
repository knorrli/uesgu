require "db_test_helper"

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

  test "the stored fingerprint reproduces Place.fingerprint_for exactly" do
    zorpsaal = place(name: "Zörp-Saal & Bar")

    assert_equal Place.fingerprint_for("Zörp-Saal & Bar"), zorpsaal.fingerprint
    assert_equal "zorpsaalandbar", zorpsaal.fingerprint
  end

  test "the stored name_folded reproduces Fingerprint.folded exactly" do
    zorpsaal = place(name: "Zörp-Saal & Bar")

    assert_equal "zorp saal and bar", zorpsaal.name_folded
    assert_equal Fingerprint.folded("Zörp-Saal & Bar"), zorpsaal.name_folded
  end

  test "spelling variants of one name cannot become two places" do
    place(name: "Zorpsaal")

    refute Place.new(name: "ZORP SAAL", locality: "Zorpwil", canton: "BE").valid?
  end

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

  test "a place may duplicate a registry venue we do not source from" do
    unsourced = Venue.all.find { |v| !Venue.in_taxonomy.include?(v) }
    skip "every registry venue is in the taxonomy" if unsourced.nil?

    assert Place.new(name: unsourced.name, locality: "Zorpwil", canton: "BE").valid?
  end

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

  def saved_filter(owner, locations)
    rule = owner.saved_filters.new(cadence: "daily", time_of_day: 18 * 60)
    rule.filter_attributes = { l: locations }
    rule.save!
    rule
  end

  test "a merge retags the events carrying the old name" do
    akut = place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    variant = place(name: "AKUT Zorpwil", locality: "Zorpwil", canton: "BE")
    show = event(location_list: ["AKUT Zorpwil", "Zorpwil", "BE"])

    variant.merge_into!(akut)

    assert_includes show.reload.location_list, "AKuT"
    refute_includes show.location_list, "AKUT Zorpwil"
  end

  test "a merge moves the events onto the canonical's town and canton" do
    akut = place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    variant = place(name: "Flarnhalle", locality: "Flarnhausen", canton: "AG")
    show = event(location_list: ["Flarnhalle", "Flarnhausen", "AG"])

    variant.merge_into!(akut)

    assert_equal %w[AKuT BE Zorpwil], show.reload.location_list.to_a.sort
  end

  test "a merged name keeps resolving to the canonical for everything new" do
    akut = place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    variant = place(name: "AKUT Zorpwil", locality: "Zorpwil", canton: "BE")

    variant.merge_into!(akut)

    assert_equal akut, Place.matching("AKUT Zorpwil")
    assert_predicate variant.reload, :alias?
  end

  test "merging into an alias lands on what that alias names" do
    akut = place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    first = place(name: "AKUT Zorpwil", locality: "Zorpwil", canton: "BE")
    second = place(name: "Akut Halle", locality: "Zorpwil", canton: "BE")

    first.merge_into!(akut)
    second.merge_into!(first)

    assert_equal akut, second.reload.canonical
  end

  test "merging a place that already has aliases takes them along" do
    akut = place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    middle = place(name: "AKUT Zorpwil", locality: "Zorpwil", canton: "BE")
    leaf = place(name: "Akut Halle", locality: "Zorpwil", canton: "BE")

    leaf.merge_into!(middle)
    middle.merge_into!(akut)

    assert_equal akut, leaf.reload.canonical
  end

  test "a place cannot be merged into itself, directly or through its own alias" do
    akut = place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    variant = place(name: "AKUT Zorpwil", locality: "Zorpwil", canton: "BE")
    variant.merge_into!(akut)

    assert_raises(ArgumentError) { akut.merge_into!(akut) }
    assert_raises(ArgumentError) { akut.merge_into!(variant.reload) }
  end

  test "a place the registry has absorbed cannot be merged away" do
    venue = Venue.in_taxonomy.first
    skip "no venues in the taxonomy" if venue.nil?

    graduated = Place.new(name: venue.name, locality: venue.locality, canton: venue.canton)
    graduated.save!(validate: false)

    assert_raises(ArgumentError) { graduated.merge_into!(place(name: "Zorpsaal")) }
  end

  test "a merge repoints the saved filters holding the old name" do
    akut = place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    variant = place(name: "AKUT Zorpwil", locality: "Zorpwil", canton: "BE")
    watcher = saved_filter(user, ["AKUT Zorpwil"])

    variant.merge_into!(akut)

    assert_equal ["AKuT"], watcher.reload.location_list
  end

  test "a repointed filter that duplicates another of the user's filters is dropped" do
    akut = place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    variant = place(name: "AKUT Zorpwil", locality: "Zorpwil", canton: "BE")
    owner = user
    kept = saved_filter(owner, ["AKuT"])
    dropped = saved_filter(owner, ["AKUT Zorpwil"])

    variant.merge_into!(akut)

    assert_predicate SavedFilter.where(id: dropped.id), :empty?
    assert_equal ["AKuT"], kept.reload.location_list
  end

  test "a rename retags the events carrying the old spelling" do
    zorpsaal = place(name: "ZORPSAAL", locality: "Zorpwil", canton: "BE")
    show = event(location_list: ["ZORPSAAL", "Zorpwil", "BE"])

    assert zorpsaal.rename!("Zorpsaal")

    assert_equal %w[BE Zorpsaal Zorpwil], show.reload.location_list.to_a.sort
  end

  test "a rename repoints the saved filters holding the old spelling" do
    zorpsaal = place(name: "ZORPSAAL", locality: "Zorpwil", canton: "BE")
    watcher = saved_filter(user, ["ZORPSAAL"])

    zorpsaal.rename!("Zorpsaal")

    assert_equal ["Zorpsaal"], watcher.reload.location_list
  end

  test "a rename onto a spelling another place already answers to is refused" do
    place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    flarnhalle = place(name: "Flarnhalle", locality: "Flarnhausen", canton: "AG")

    refute flarnhalle.rename!("akut")

    assert_equal "Flarnhalle", flarnhalle.name
    assert_equal "Flarnhalle", flarnhalle.reload.name
  end

  test "a rename to nothing at all is refused" do
    flarnhalle = place(name: "Flarnhalle", locality: "Flarnhausen", canton: "AG")

    refute flarnhalle.rename!("   ")

    assert_equal "Flarnhalle", flarnhalle.reload.name
  end

  test "splitting undoes the link and leaves the moved events where they were moved" do
    akut = place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    variant = place(name: "AKUT Zorpwil", locality: "Zorpwil", canton: "BE")
    show = event(location_list: ["AKUT Zorpwil", "Zorpwil", "BE"])
    variant.merge_into!(akut)

    variant.unmerge!

    refute_predicate variant.reload, :alias?
    assert_includes show.reload.location_list, "AKuT"
  end
end
