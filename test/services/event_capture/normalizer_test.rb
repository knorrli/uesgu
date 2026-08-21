require "test_helper"

# Every case here is a shape the model actually returned during the provider
# evaluation. The invariant under test is always the same one: a value we cannot trust
# is nulled and kept, never coerced into something plausible.
class EventCapture::NormalizerTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 8, 19)

  def normalize(event) = EventCapture::Normalizer.call(event, today: TODAY)

  # Stands in for the taxonomy without a database: the canton half only ever asks
  # this one question of it.
  def known(**localities)
    EventCapture::Localities.new(
      localities.map { |name, canton| EventCapture::Localities::Entry.new(name: name.to_s, canton: canton) }
    )
  end

  def normalize_with_genres(event, *known)
    EventCapture::Normalizer.call(event, today: TODAY, genres: EventCapture::Genres.for_names(known))
  end

  def normalize_in(event, **localities)
    EventCapture::Normalizer.call(event, today: TODAY, localities: known(**localities))
  end

  def dated(**overrides)
    { "date" => "2026-08-20", "date_evidence" => "Do 20. August" }.merge(overrides.stringify_keys)
  end

  def cited_locality(name, **overrides)
    { "locality" => name, "locality_evidence" => "3000 #{name}" }.merge(overrides.stringify_keys)
  end

  test "a well-formed event passes through" do
    candidate = normalize(dated(
      "title" => " Zorpcore Nacht ", "time" => "20:00", "place" => "Zorpsaal",
      "place_evidence" => "Zorpsaal, Zorpwil", "locality" => "Zorpwil",
      "locality_evidence" => "3000 Zorpwil", "canton" => "BE",
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

  test "a cited subtitle survives with the line it was read from" do
    candidate = normalize(dated("subtitle" => " message: incomplete ",
                                "subtitle_evidence" => "message: incomplete"))

    assert_equal "message: incomplete", candidate.subtitle
    assert_equal "message: incomplete", candidate.subtitle_evidence
    assert_empty candidate.issues
  end

  test "an uncited subtitle is dropped and kept" do
    candidate = normalize("subtitle" => "Zorpwils feinste Nacht", "subtitle_evidence" => nil)

    assert_nil candidate.subtitle
    assert_equal "Zorpwils feinste Nacht", candidate.raw["subtitle"]
    assert_includes candidate.issues, :subtitle_uncited
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

  # A two-letter origin code printed beside an act name is what filled this field
  # before it had to be cited, and "Us" is a well-formed string nothing else refuses.
  test "an uncited locality is dropped and kept" do
    candidate = normalize("locality" => "Us", "locality_evidence" => nil)

    assert_nil candidate.locality
    assert_equal "Us", candidate.raw["locality"]
    assert_includes candidate.issues, :locality_uncited
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

  # The sample posters were all German, so a parser built from their vocabulary would
  # encode an accident of six inputs. These are the shapes the long tail carries.
  test "French, English and marker-less clock formats normalise too" do
    { "20h30" => "20:30", "20 h 30" => "20:30", "20h" => "20:00", "21 heures" => "21:00",
      "8pm" => "20:00", "8:30 PM" => "20:30", "12 am" => "00:00", "12pm" => "12:00",
      "9 o'clock" => "09:00", "20.00" => "20:00", "20:00-23:00" => "20:00" }.each do |printed, expected|
      assert_equal expected, normalize("time" => printed).time, printed
    end
  end

  test "a date in the time field is not read as a time" do
    ["20.08.", "20.08.2026", "31.12."].each do |printed|
      candidate = normalize("time" => printed)

      assert_nil candidate.time, printed
      assert_equal printed, candidate.raw["time"]
    end
  end

  test "a time that does not lead with the clock is nulled rather than guessed" do
    assert_nil normalize("time" => "Doors 19:00").time
    assert_nil normalize("time" => "halb acht").time
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

  test "a known locality supplies the canton the model left blank" do
    candidate = normalize_in(cited_locality("Zorpwil", "canton" => nil), Zorpwil: "BE")

    assert_equal "BE", candidate.canton
    assert_empty candidate.issues
    assert_empty candidate.raw
  end

  test "the computed canton beats the model's, and the disagreement is kept" do
    candidate = normalize_in(cited_locality("Zorpwil", "canton" => "AG"), Zorpwil: "BE")

    assert_equal "BE", candidate.canton
    assert_equal "AG", candidate.raw["canton"]
    assert_includes candidate.issues, :canton_recomputed
  end

  test "agreeing with the computed canton is not a disagreement" do
    candidate = normalize_in(cited_locality("Zorpwil", "canton" => "be"), Zorpwil: "BE")

    assert_equal "BE", candidate.canton
    assert_empty candidate.issues
    assert_empty candidate.raw
  end

  # The case computation cannot serve, and the reason the field stays in the schema.
  test "a locality nobody carries leaves the model's canton standing" do
    candidate = normalize_in(cited_locality("Flarnhausen", "canton" => "AG"), Zorpwil: "BE")

    assert_equal "AG", candidate.canton
    assert_empty candidate.issues
  end

  test "an uncited locality computes nothing — there is no locality to compute from" do
    candidate = normalize_in({ "locality" => "Zorpwil", "locality_evidence" => nil, "canton" => "AG" },
                             Zorpwil: "BE")

    assert_nil candidate.locality
    assert_equal "AG", candidate.canton
    assert_includes candidate.issues, :locality_uncited
  end

  test "a canton the computation cannot replace is still refused" do
    candidate = normalize_in(cited_locality("Flarnhausen", "canton" => "Bern"), Zorpwil: "BE")

    assert_nil candidate.canton
    assert_equal "Bern", candidate.raw["canton"]
    assert_includes candidate.issues, :canton_invalid
  end

  test "a known locality replaces a junk canton without flagging it twice" do
    candidate = normalize_in(cited_locality("Zorpwil", "canton" => "Bern"), Zorpwil: "BE")

    assert_equal "BE", candidate.canton
    assert_equal "Bern", candidate.raw["canton"]
    assert_equal [:canton_invalid], candidate.issues
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

  # A quote can legitimately span more than one date ("Fr 20. & Sa 21. Februar" on a
  # two-night poster). Taking the resolver's whole answer there turned a wrong year
  # into a wrong show.
  test "evidence describing another date corrects nothing and says so" do
    candidate = normalize("date" => "2026-02-20", "date_evidence" => "Fr 20. & Sa 21. Februar")

    assert_equal Date.new(2026, 2, 20), candidate.date
    assert_includes candidate.issues, :date_evidence_mismatch
    assert_empty candidate.raw
  end

  # A weekday that contradicts the date is surfaced, never obeyed (see
  # YearResolver.weekday_conflict? for what it cost as a selector).
  test "a contradicting weekday is flagged and the date left alone" do
    candidate = normalize("date" => "2026-08-19", "date_evidence" => "Di 19. August")

    assert_equal Date.new(2026, 8, 19), candidate.date
    assert_includes candidate.issues, :date_weekday_conflict
  end

  test "a weekday that agrees raises nothing" do
    assert_empty normalize("date" => "2026-08-19", "date_evidence" => "Mi 19. August").issues
  end

  test "a rejected datetime is kept in raw as the model wrote it" do
    candidate = normalize("date" => "2026-02-30T20:00:00", "date_evidence" => "30. Februar")

    assert_nil candidate.date
    assert_equal "2026-02-30T20:00:00", candidate.raw["date"]
  end

  # Observed on a real poster: six genres arrived as one string. The taxonomy is what
  # says the slash is a separator (see EventCapture::Genres).
  test "a slash run the taxonomy vouches for becomes several genres" do
    candidate = normalize_with_genres({ "genres" => ["Loops/Zorpcore/FX"] }, "Zorpcore")

    assert_equal %w[Loops Zorpcore FX], candidate.genres
    assert_includes candidate.issues, :genres_split
  end

  # Splitting refuses nothing, so there is no refused value to keep — the flag is the
  # whole record that the rule fired.
  test "a run nothing vouches for stays one genre and raises nothing" do
    candidate = normalize_with_genres({ "genres" => ["Loops/FX"] }, "Zorpcore")

    assert_equal ["Loops/FX"], candidate.genres
    assert_empty candidate.issues
    assert_empty candidate.raw
  end

  test "genres reach the card unsplit where the taxonomy is not there to ask" do
    assert_equal ["Loops/FX"], normalize("genres" => ["Loops/FX"]).genres
  end

  test "past is computed, never asked of the model" do
    assert normalize(dated("date" => "2026-08-01", "date_evidence" => "1. August")).past?(today: TODAY)
    refute normalize(dated).past?(today: TODAY)
    refute normalize({}).past?(today: TODAY)
  end
end
