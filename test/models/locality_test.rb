require "db_test_helper"

class LocalityTest < ActiveSupport::TestCase
  def locality(name, canton: nil) = Locality.create!(name: name, canton: canton)

  def saved_filter(owner, locations)
    rule = owner.saved_filters.new(cadence: "daily", time_of_day: 18 * 60)
    rule.filter_attributes = { l: locations }
    rule.save!
    rule
  end

  test "the stored fingerprint reproduces Fingerprint.for exactly" do
    zorpwil = locality("Zörp-Wil & Umgebung")

    assert_equal Fingerprint.for("Zörp-Wil & Umgebung"), zorpwil.fingerprint
    assert_equal "zorpwilandumgebung", zorpwil.fingerprint
  end

  test "a typed name matches modulo case, accents and punctuation" do
    zorpwil = locality("Zorpwil", canton: "BE")

    assert_equal zorpwil, Locality.matching("ZORP-WIL")
    assert_equal "Zorpwil", Locality.canonical_name("zorpwîl")
    assert_equal "BE", Locality.canton_for("zorp wil")
  end

  test "a name nobody carries is left as typed, with no canton" do
    locality("Zorpwil", canton: "BE")

    assert_equal "Flarnhausen", Locality.canonical_name("Flarnhausen")
    assert_nil Locality.canton_for("Flarnhausen")
    assert_equal "", Locality.canonical_name("")
    assert_nil Locality.canton_for("")
  end

  test "ensure! mints one row per fingerprint and never a second" do
    Locality.ensure!(["Zorpwil", "ZORP-WIL", " ", nil, "..."])
    Locality.ensure!(["zorpwil"])

    assert_equal ["Zorpwil"], Locality.pluck(:name)
  end

  test "reconcile! reads the venue registry, the captured places and the tags" do
    place(name: "Flarnhalle", locality: "Flarnhausen", canton: "AG")
    event(location_list: ["Zorpville", "SO"])
    Locality.reconcile!

    assert_equal "AG", Locality.canton_for("flarnhausen")
    assert_equal 1, Locality.matching("Zorpville").events_count
    venue = Venue.in_taxonomy.find { |v| v.locality.present? }
    assert_equal venue.canton, Locality.canton_for(venue.locality) if venue
  end

  test "reconcile! abstains on a canton its sources disagree about" do
    place(name: "Flarnhalle", locality: "Zorpwil", canton: "AG")
    place(name: "Zorphalle", locality: "Zorpwil", canton: "SO")
    Locality.reconcile!

    assert_nil Locality.canton_for("Zorpwil")
  end

  test "reconcile! names a town for the spelling the most events carry" do
    2.times { event(location_list: ["Zorpwil"]) }
    event(location_list: ["ZORPWIL"])

    3.times { Locality.reconcile! }

    assert_equal "Zorpwil", Locality.matching("zorpwil").name
  end

  test "spellings the same number of events carry break alphabetically" do
    event(location_list: ["Zorpwil"])
    event(location_list: ["ZORPWIL"])

    Locality.reconcile!

    assert_equal "ZORPWIL", Locality.matching("zorpwil").name
  end

  test "reconcile! files a stranded spelling under the town's own name" do
    rule = saved_filter(user, ["ZORPWIL"])
    2.times { event(location_list: ["Zorpwil", "BE"]) }
    stranded = event(location_list: ["ZORPWIL", "BE"])

    Locality.reconcile!

    assert_equal "Zorpwil", Locality.matching("zorpwil").name
    assert_includes stranded.reload.location_list, "Zorpwil"
    refute_includes stranded.location_list, "ZORPWIL"
    assert_equal ["Zorpwil"], rule.reload.location_list
    assert_includes rule.matched_events, stranded
  end

  test "reconcile! moves a captured place off a stranded spelling" do
    place(name: "Flarnhalle", locality: "Zorpwil", canton: "BE")
    stray = place(name: "Zorphalle", locality: "zorpwil", canton: "BE")
    event(location_list: ["Zorphalle", "zorpwil", "BE"])

    Locality.reconcile!

    assert_equal "Zorpwil", stray.reload.locality
  end

  test "reconcile! does not fold a locality whose tags all read the canonical way" do
    saved_filter(user, ["Zorpwil"])
    event(location_list: ["Zorpwil", "BE"])
    Locality.reconcile!

    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      statements << payload[:sql]
    end
    Locality.reconcile!
    ActiveSupport::Notifications.unsubscribe(subscriber)

    refute statements.any? { |sql| sql.include?("saved_filters") },
           "the fold ran on a locality with nothing to fold"
  end

  test "reconcile! zeroes a locality nothing carries any more" do
    stale = locality("Zorpville")
    stale.update!(events_count: 7)
    Locality.reconcile!

    assert_equal 0, stale.reload.events_count
  end

  test "a merge retags the events carrying the old name" do
    zorpwil = locality("Zorpwil", canton: "BE")
    zorpville = locality("Zorpville", canton: "BE")
    show = event(location_list: ["Zorpsaal", "Zorpville", "BE"])

    zorpville.merge_into!(zorpwil)

    assert_includes show.reload.location_list, "Zorpwil"
    refute_includes show.location_list, "Zorpville"
  end

  test "a merge moves the captured places under the old name" do
    zorpwil = locality("Zorpwil", canton: "BE")
    zorpville = locality("Zorpville", canton: "BE")
    hall = place(name: "Flarnhalle", locality: "ZORP-VILLE", canton: "BE")

    zorpville.merge_into!(zorpwil)

    assert_equal "Zorpwil", hall.reload.locality
  end

  test "a merged name keeps resolving to the canonical for everything new" do
    zorpwil = locality("Zorpwil", canton: "BE")
    zorpville = locality("Zorpville")

    zorpville.merge_into!(zorpwil)

    assert_predicate zorpville.reload, :alias?
    assert_equal "Zorpwil", Locality.canonical_name("zorpville")
    assert_equal "BE", Locality.canton_for("Zorpville")
  end

  test "a merged name is no longer offered as its own option" do
    zorpwil = locality("Zorpwil", canton: "BE")
    locality("Zorpville").merge_into!(zorpwil)

    offered = Locality.cantons_by_name

    assert_equal "BE", offered["Zorpwil"]
    refute_includes offered.keys, "Zorpville"
  end

  test "merging into an alias lands on what that alias names" do
    zorpwil = locality("Zorpwil", canton: "BE")
    zorpville = locality("Zorpville")
    zorpville.merge_into!(zorpwil)

    flarn = locality("Flarnwil")
    flarn.merge_into!(zorpville.reload)

    assert_equal zorpwil, flarn.reload.canonical
    assert_equal "Zorpwil", Locality.canonical_name("Flarnwil")
  end

  test "merging a locality that already has aliases takes them along" do
    zorpwil = locality("Zorpwil", canton: "BE")
    zorpville = locality("Zorpville")
    flarn = locality("Flarnwil")
    flarn.merge_into!(zorpville)

    zorpville.merge_into!(zorpwil)

    assert_equal zorpwil, flarn.reload.canonical
    assert_equal "Zorpwil", Locality.canonical_name("Flarnwil")
  end

  test "a locality cannot be merged into itself, directly or through its own alias" do
    zorpwil = locality("Zorpwil", canton: "BE")
    zorpville = locality("Zorpville")
    zorpville.merge_into!(zorpwil)

    assert_raises(ArgumentError) { zorpwil.merge_into!(zorpwil) }
    assert_raises(ArgumentError) { zorpwil.merge_into!(zorpville.reload) }
  end

  test "a locality the venue registry names cannot be merged away" do
    venue = Venue.in_taxonomy.find { |v| v.locality.present? }
    skip "no placed venue" if venue.nil?
    Locality.reconcile!
    registry = Locality.matching(venue.locality)

    assert_predicate registry, :registry?
    assert_raises(ArgumentError) { registry.merge_into!(locality("Zorpwil", canton: "BE")) }
  end

  test "a captured spelling merges INTO a registry locality just fine" do
    venue = Venue.in_taxonomy.find { |v| v.locality.present? }
    skip "no placed venue" if venue.nil?
    Locality.reconcile!
    zorpville = locality("Zorpville")

    zorpville.merge_into!(Locality.matching(venue.locality))

    assert_equal venue.locality, Locality.canonical_name("zorpville")
  end

  test "a merge repoints the saved filters holding the old name" do
    zorpwil = locality("Zorpwil", canton: "BE")
    zorpville = locality("Zorpville", canton: "BE")
    rule = saved_filter(user, ["ZORP-VILLE", "Flarnhausen"])
    show = event(location_list: ["Zorpville", "BE"])

    zorpville.merge_into!(zorpwil)

    assert_equal ["Zorpwil", "Flarnhausen"], rule.reload.location_list
    assert_includes rule.name, "Zorpwil"
    assert_includes rule.matched_events, show
  end

  test "a filter holding both spellings is left with one" do
    zorpwil = locality("Zorpwil", canton: "BE")
    zorpville = locality("Zorpville", canton: "BE")
    rule = saved_filter(user, ["Zorpville", "Zorpwil"])

    zorpville.merge_into!(zorpwil)

    assert_equal ["Zorpwil"], rule.reload.location_list
  end

  test "a repointed filter that duplicates another of the user's filters is dropped" do
    zorpwil = locality("Zorpwil", canton: "BE")
    zorpville = locality("Zorpville", canton: "BE")
    owner = user
    kept = saved_filter(owner, ["Zorpwil"])
    saved_filter(owner, ["Zorpville"])

    zorpville.merge_into!(zorpwil)

    assert_equal [kept], owner.saved_filters.reload.to_a
  end

  test "the duplicate check is per owner" do
    zorpwil = locality("Zorpwil", canton: "BE")
    zorpville = locality("Zorpville", canton: "BE")
    mine = saved_filter(user, ["Zorpville"])
    yours = saved_filter(user, ["Zorpwil"])

    zorpville.merge_into!(zorpwil)

    assert_equal ["Zorpwil"], mine.reload.location_list
    assert_equal ["Zorpwil"], yours.reload.location_list
  end

  test "feed highlighting follows a repointed saved filter" do
    zorpwil = locality("Zorpwil", canton: "BE")
    zorpville = locality("Zorpville", canton: "BE")
    owner = user
    saved_filter(owner, ["Zorpville"])
    show = event(location_list: ["Zorpville", "BE"])

    zorpville.merge_into!(zorpwil)

    assert_includes InterestProfile.for(owner).why_locations(show.reload).map(&:name), "Zorpwil"
  end

  test "splitting undoes the link and leaves the moved data where it was moved" do
    zorpwil = locality("Zorpwil", canton: "BE")
    zorpville = locality("Zorpville")
    show = event(location_list: ["Zorpville", "BE"])
    rule = saved_filter(user, ["Zorpville"])
    zorpville.merge_into!(zorpwil)

    zorpville.reload.unmerge!

    refute_predicate zorpville.reload, :alias?
    assert_equal "Zorpville", Locality.canonical_name("zorpville")
    assert_includes show.reload.location_list, "Zorpwil"
    assert_equal ["Zorpwil"], rule.reload.location_list
  end
end
