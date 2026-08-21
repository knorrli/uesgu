require "db_test_helper"

# The ranking behind the capture card's suggestion rows. The place chips are the
# suggester's answer as it stands; the locality chips are what is left of it once
# the towns are what is being offered.
class CapturesHelperTest < ActionView::TestCase
  def suggestion(name, locality, canton = "BE")
    PlaceSuggester::Suggestion.new(name: name, locality: locality, canton: canton,
                                   source: "place", score: 1.0)
  end

  test "a place chip carries the whole tuple it fills" do
    chip = place_chips([suggestion("Zorpsaal", "Zorpwil")]).sole

    assert_equal "Zorpsaal", chip[:label]
    assert_equal "capture#applySuggestion", chip[:attrs][:data][:action]
    assert_equal "Zorpwil", chip[:attrs][:data][:capture_locality_param]
    assert_equal "BE", chip[:attrs][:data][:capture_canton_param]
  end

  test "the towns of the venues being suggested are the locality chips" do
    chips = locality_chips([suggestion("Zorpsaal", "Zorpwil"),
                            suggestion("Flarnhalle", "Flarnhausen", "AG")])

    assert_equal %w[Zorpwil Flarnhausen], chips.map { |chip| chip[:label] }
    assert_equal "capture#applyLocality", chips.first[:attrs][:data][:action]
    assert_equal "AG", chips.last[:attrs][:data][:capture_canton_param]
  end

  # Two venues in one town is one town, and two spellings of that town are still one:
  # offering both is how the field fills with the near-duplicates it exists to prevent.
  test "one town is one chip, however its venues spell it" do
    chips = locality_chips([suggestion("Zorpsaal", "Zorpwil"),
                            suggestion("Zorpkeller", "Zorpwil"),
                            suggestion("Zorphalle", "ZORP-WIL")])

    assert_equal %w[Zorpwil], chips.map { |chip| chip[:label] }
  end

  test "a venue carrying no town offers none" do
    assert_empty locality_chips([suggestion("Zorpsaal", nil), suggestion("Zorphalle", "")])
  end
end
