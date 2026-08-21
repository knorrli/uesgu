require "db_test_helper"

# The rows behind both halves of locality handling: which stored spelling a typed
# locality is, and which canton that puts it in. Synthetic locality names; the
# registry is read live.
class EventCapture::LocalitiesTest < ActiveSupport::TestCase
  def localities(*entries)
    EventCapture::Localities.new(entries.map { |name, canton| EventCapture::Localities::Entry.new(name: name, canton: canton) })
  end

  test "a typed locality adopts the stored spelling modulo case, accents and punctuation" do
    known = localities(["Zorpwil", "BE"])

    assert_equal "Zorpwil", known.canonical("ZORP-WIL")
    assert_equal "Zorpwil", known.canonical("zorpwîl")
  end

  test "a locality nobody carries is left exactly as typed" do
    assert_equal "Flarnhausen", localities(["Zorpwil", "BE"]).canonical("Flarnhausen")
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

  test "reads the registry and captured places, registry spelling first" do
    venue = Venue.in_taxonomy.find { |v| v.locality.present? }
    skip "no placed venue" if venue.nil?
    place(name: "Flarnhalle", locality: "Flarnhausen", canton: "AG")

    known = EventCapture::Localities.known

    assert_equal venue.locality, known.canonical(venue.locality.downcase)
    assert_equal venue.canton, known.canton_for(venue.locality)
    assert_equal "AG", known.canton_for("flarnhausen")
  end
end
