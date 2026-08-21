require "db_test_helper"

# The rows behind both halves of locality handling: which stored spelling a typed
# locality is, and which canton that puts it in. Synthetic locality names; the
# registry is read live.
class EventCapture::LocalitiesTest < ActiveSupport::TestCase
  # The curated aliases are synthetic here for the same reason the names are: the
  # real list is a data file, tested against itself in EventCapture::LocalityAliasesTest.
  def localities(*entries, aliases: {})
    EventCapture::Localities.new(
      entries.map { |name, canton| EventCapture::Localities::Entry.new(name: name, canton: canton) },
      aliases: EventCapture::LocalityAliases.new(aliases)
    )
  end

  test "a typed locality adopts the stored spelling modulo case, accents and punctuation" do
    known = localities(["Zorpwil", "BE"])

    assert_equal "Zorpwil", known.canonical("ZORP-WIL")
    assert_equal "Zorpwil", known.canonical("zorpwîl")
  end

  test "a locality nobody carries is left exactly as typed" do
    assert_equal "Flarnhausen", localities(["Zorpwil", "BE"]).canonical("Flarnhausen")
  end

  test "a curated variant adopts the canonical spelling it is an alias for" do
    known = localities(["Zorpwil", "BE"], aliases: { "Zorpwil" => ["Zorpville"] })

    assert_equal "Zorpwil", known.canonical("Zorpville")
    assert_equal "Zorpwil", known.canonical("ZORP-VILLE")
  end

  # The whole point where a fresh spelling enters: the alias decides which of the two
  # names the first event under it is filed as, before either exists.
  test "a variant of a locality nobody carries yet still adopts the canonical spelling" do
    known = localities(["Zorpwil", "BE"], aliases: { "Flarnhausen" => ["Flarnville"] })

    assert_equal "Flarnhausen", known.canonical("Flarnville")
  end

  test "a curated variant is placed in the canton its canonical sits in" do
    known = localities(["Zorpwil", "BE"], aliases: { "Zorpwil" => ["Zorpville"] })

    assert_equal "BE", known.canton_for("Zorpville")
  end

  # The datalist offers names to pick, and an alias is not one: two rows for one town
  # is exactly what the aliases exist to prevent.
  test "a curated variant is never offered as its own option" do
    known = localities(["Zorpwil", "BE"], aliases: { "Zorpwil" => ["Zorpville"] })

    assert_equal({ "Zorpwil" => "BE" }, known.cantons_by_name)
  end

  test "a known locality names its own canton" do
    assert_equal "BE", localities(["Zorpwil", "BE"]).canton_for("zorpwil")
  end

  test "a locality nobody carries has no canton to compute" do
    assert_nil localities(["Zorpwil", "BE"]).canton_for("Flarnhausen")
  end

  test "a blank locality is neither rewritten nor placed" do
    known = localities(["Zorpwil", "BE"])

    assert_equal "", known.canonical("")
    assert_nil known.canton_for("")
  end

  test "a name carried under two cantons abstains rather than picking one" do
    assert_nil localities(["Zorpwil", "BE"], ["Zorpwil", "AG"]).canton_for("Zorpwil")
  end

  # "" would read as present all the way to publish, and land the event under a
  # branch of the WHERE tree that does not exist.
  test "a locality carried without a canton computes nothing rather than a blank" do
    assert_nil localities(["Zorpwil", ""]).canton_for("Zorpwil")
  end

  test "the same name under one canton twice is not ambiguous" do
    assert_equal "BE", localities(["Zorpwil", "BE"], ["Zorp-wil", "BE"]).canton_for("Zorpwil")
  end

  test "the offered names carry the canton picking them computes to" do
    assert_equal({ "Zorpwil" => "BE", "Flarnhausen" => "AG" },
                 localities(["Zorpwil", "BE"], ["Flarnhausen", "AG"]).cantons_by_name)
  end

  test "an ambiguous name is still offered, with nothing to fill from it" do
    assert_equal({ "Zorpwil" => nil }, localities(["Zorpwil", "BE"], ["Zorpwil", "AG"]).cantons_by_name)
  end

  test "two spellings of one name are one option, under the registry's" do
    assert_equal({ "Zorpwil" => "BE" }, localities(["Zorpwil", "BE"], ["ZORP-WIL", "BE"]).cantons_by_name)
  end

  test "reads the registry and captured places, registry spelling first" do
    venue = Venue.in_taxonomy.find { |v| v.locality.present? }
    skip "no placed venue" if venue.nil?
    place(name: "Flarnhalle", locality: "Flarnhausen", canton: "AG")

    known = EventCapture::Localities.known

    assert_equal venue.locality, known.canonical(venue.locality.downcase)
    assert_equal venue.canton, known.canton_for(venue.locality)
    assert_equal "AG", known.canton_for("flarnhausen")
  end

  # The wiring, on real data: Fribourg is in the registry and Freiburg is in the
  # curated list, and neither half is any use without the other.
  test "the curated list is the one the taxonomy's own lookup reads" do
    skip "Fribourg is no longer in the registry" if Venue.in_taxonomy.none? { |v| v.locality == "Fribourg" }

    assert_equal "Fribourg", EventCapture::Localities.known.canonical("Freiburg")
  end
end
