require "db_test_helper"

class CapturesHelperTest < ActionView::TestCase
  def suggestion(name, locality, canton = "BE")
    PlaceSuggester::Suggestion.new(name: name, locality: locality, canton: canton,
                                   source: "place", score: 1.0)
  end

  def candidate(**attrs) = EventCapture::Candidate.new(**attrs)

  test "the canton picker offers every code, ordered by code" do
    assert_equal Location::CANTON_CODES.sort, canton_options
    assert_equal %w[AG ZH], canton_options.values_at(0, -1)
  end

  test "a place chip carries the whole tuple it fills" do
    chip = place_chips([suggestion("Zorpsaal", "Zorpwil")], "capture").sole

    assert_equal "Zorpsaal", chip[:label]
    assert_equal "capture#applySuggestion", chip[:attrs][:data][:action]
    assert_equal "Zorpwil", chip[:attrs][:data]["capture_locality_param"]
    assert_equal "BE", chip[:attrs][:data]["capture_canton_param"]
  end

  test "a chip is keyed for the controller the screen mounts" do
    chip = place_chips([suggestion("Zorpsaal", "Zorpwil")], "manual-capture").sole

    assert_equal "manual-capture#applySuggestion", chip[:attrs][:data][:action]
    assert_equal "Zorpsaal", chip[:attrs][:data]["manual_capture_name_param"]
    assert_equal "Zorpwil", chip[:attrs][:data]["manual_capture_locality_param"]
  end

  test "near names are offered where none of them is the name itself" do
    place(name: "Zorpsaal", locality: "Zorpwil")

    suggestions = place_suggestions(candidate(place: "Zorpsal", locality: "Zorpwil"))

    assert_equal %w[Zorpsaal], suggestions.map(&:name)
  end

  test "a name the app already carries leaves nothing to suggest" do
    place(name: "Zorpsaal", locality: "Zorpwil")
    place(name: "Zorpsaal Keller", locality: "Zorpwil")

    assert_empty place_suggestions(candidate(place: "Zorpsaal", locality: "Zorpwil"))
  end

  test "a name matching one only once folded leaves nothing to suggest either" do
    place(name: "Zorpsaal", locality: "Zorpwil")

    assert_equal %w[Zorpsaal], PlaceSuggester.for_name("ZORPSAAL").map(&:name)
    assert_empty place_suggestions(candidate(place: "ZORPSAAL", locality: "Zorpwil"))
  end

  test "the towns of the venues being suggested are the locality chips" do
    chips = locality_chips([suggestion("Zorpsaal", "Zorpwil"),
                            suggestion("Flarnhalle", "Flarnhausen", "AG")], candidate, "capture")

    assert_equal %w[Zorpwil Flarnhausen], chips.map { |chip| chip[:label] }
    assert_equal "capture#applyLocality", chips.first[:attrs][:data][:action]
    assert_equal "AG", chips.last[:attrs][:data]["capture_canton_param"]
  end

  test "one town is one chip, however its venues spell it" do
    chips = locality_chips([suggestion("Zorpsaal", "Zorpwil"),
                            suggestion("Zorpkeller", "Zorpwil"),
                            suggestion("Zorphalle", "ZORP-WIL")], candidate, "capture")

    assert_equal %w[Zorpwil], chips.map { |chip| chip[:label] }
  end

  test "a venue carrying no town offers none" do
    assert_empty locality_chips([suggestion("Zorpsaal", nil), suggestion("Zorphalle", "")],
                                candidate, "capture")
  end

  test "a town the card is already filed under is not offered back to it" do
    chips = locality_chips([suggestion("Zorpsaal", "Zorpwil"),
                            suggestion("Flarnhalle", "Flarnhausen", "AG")],
                           candidate(locality: "Zorpwil", canton: "BE"), "capture")

    assert_equal %w[Flarnhausen], chips.map { |chip| chip[:label] }
  end

  test "that town is offered while the canton beside it is still empty" do
    chips = locality_chips([suggestion("Zorpsaal", "Zorpwil")], candidate(locality: "Zorpwil"),
                           "capture")

    assert_equal %w[Zorpwil], chips.map { |chip| chip[:label] }
  end
end
