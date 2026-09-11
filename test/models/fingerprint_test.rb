require "db_test_helper"

class FingerprintTest < ActiveSupport::TestCase
  NAMES = [
    "Ü-30 Party", "Österreich", "Ägypten", "ÉCLAT", "Çà et Là", "ÎLE FLOTTANTE",
    "ÔDE", "ÛBERWAVE", "ËLLE", "ÏSLE", "ÀÂ Drone", "ÈÊ Core",
    "Hip-Hop", "Drum & Bass", "Rock'n'Roll", "flärnbass"
  ].freeze

  test "the stored fingerprint matches Fingerprint.for, whatever the database ctype" do
    NAMES.each do |name|
      assert_equal Fingerprint.for(name), Genre.create!(name: name).reload.fingerprint,
                   "#{name.inspect} fingerprints differently in Ruby and in Postgres"
    end
  end

  test "a locality and a place fingerprint the same way a genre does" do
    NAMES.each do |name|
      assert_equal Fingerprint.for(name), Locality.create!(name: name).reload.fingerprint, name
      place = Place.create!(name: name, locality: "Zorpwil", canton: "BE")
      assert_equal Fingerprint.for(name), place.reload.fingerprint, name
      assert_equal Fingerprint.folded(name), place.name_folded, name
    end
  end

  test "an uppercase accent folds to the same letter its lowercase does" do
    assert_equal Fingerprint.for("über drone"), Genre.create!(name: "Über Drone").reload.fingerprint
  end
end
