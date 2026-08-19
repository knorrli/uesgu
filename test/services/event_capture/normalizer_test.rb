require "test_helper"

# The validators the bake-off proved we need. Every case here is a shape the model
# actually returned; the invariant under test is always the same one — a value we
# cannot trust is nulled and kept, never coerced into something plausible.
class EventCapture::NormalizerTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 8, 19)

  def normalize(event) = EventCapture::Normalizer.call(event, today: TODAY)

  def dated(**overrides)
    { "date" => "2026-08-20", "date_evidence" => "Do 20. August" }.merge(overrides.stringify_keys)
  end

  test "a well-formed event passes through" do
    candidate = normalize(dated(
      "title" => " Zorpcore Nacht ", "time" => "20:00", "place" => "Zorpsaal",
      "place_evidence" => "Zorpsaal, Zorpwil", "locality" => "Zorpwil", "canton" => "BE",
      "genres" => ["Zorpcore", " ", nil], "source_url" => "https://zorp.test/gig"
    ))

    assert_equal "Zorpcore Nacht", candidate.title
    assert_equal Date.new(2026, 8, 20), candidate.date
    assert_equal "20:00", candidate.time
    assert_equal "Zorpsaal", candidate.place
    assert_equal "BE", candidate.canton
    assert_equal ["Zorpcore"], candidate.genres
    assert_empty candidate.issues
    assert_empty candidate.raw
  end

  test "a date the model could not quote is invention, so it is dropped and kept" do
    candidate = normalize("date" => "2026-08-20", "date_evidence" => nil)

    assert_nil candidate.date
    assert_equal "2026-08-20", candidate.raw["date"]
    assert_includes candidate.issues, :date_uncited
  end

  test "an uncited place is dropped and kept — an invented venue is the costly one" do
    candidate = normalize("place" => "Café Liebig", "place_evidence" => nil)

    assert_nil candidate.place
    assert_equal "Café Liebig", candidate.raw["place"]
    assert_includes candidate.issues, :place_uncited
  end

  test "a datetime is a right answer in a wrong shape: split it, don't bin it" do
    candidate = normalize(dated("date" => "2026-08-20T19:30:00"))

    assert_equal Date.new(2026, 8, 20), candidate.date
    assert_equal "19:30", candidate.time
    assert_includes candidate.issues, :date_was_datetime
  end

  test "a salvaged datetime never overwrites a time the model stated" do
    candidate = normalize(dated("date" => "2026-08-20T19:30:00", "time" => "21:00"))

    assert_equal "21:00", candidate.time
  end

  test "the poster's own date wording is not a date" do
    candidate = normalize(dated("date" => "Mi 19. August"))

    assert_nil candidate.date
    assert_equal "Mi 19. August", candidate.raw["date"]
    assert_includes candidate.issues, :date_not_iso
  end

  test "the year is recomputed from the evidence and beats the model's answer" do
    candidate = normalize("date" => "2025-08-19", "date_evidence" => "Mi 19. August")

    assert_equal Date.new(2026, 8, 19), candidate.date
    assert_equal "2025-08-19", candidate.raw["date"]
    assert_includes candidate.issues, :year_recomputed
  end

  test "every time format the bake-off returned normalises to HH:MM" do
    { "20:00" => "20:00", "20 Uhr" => "20:00", "19:30h" => "19:30",
      "19.30h" => "19:30", "20:30 Uhr" => "20:30", "9" => "09:00" }.each do |printed, expected|
      assert_equal expected, normalize("time" => printed).time, printed
    end
  end

  test "a time that is neither a clock nor a number is dropped and kept" do
    candidate = normalize("time" => "doors at dusk")

    assert_nil candidate.time
    assert_equal "doors at dusk", candidate.raw["time"]
    assert_includes candidate.issues, :time_unparseable
  end

  test "an impossible clock time is not a time" do
    assert_nil normalize("time" => "25:70").time
  end

  test "a canton is checked against the 26 and upcased" do
    assert_equal "BE", normalize("canton" => "be").canton

    candidate = normalize("canton" => "Bern")
    assert_nil candidate.canton
    assert_equal "Bern", candidate.raw["canton"]
    assert_includes candidate.issues, :canton_invalid
  end

  test "a null locality survives extraction — it is required at persist, not here" do
    candidate = normalize(dated("locality" => nil))

    assert_nil candidate.locality
    assert_empty candidate.issues
  end

  test "a place is passed through verbatim, since match-at-entry scores what was printed" do
    candidate = normalize("place" => "  Marzili Quartierfest ", "place_evidence" => "Marzili Quartierfest")

    assert_equal "Marzili Quartierfest", candidate.place
  end

  test "past is computed, never asked of the model" do
    assert normalize(dated("date" => "2026-08-01", "date_evidence" => "1. August")).past?(today: TODAY)
    refute normalize(dated).past?(today: TODAY)
    refute normalize({}).past?(today: TODAY)
  end
end
