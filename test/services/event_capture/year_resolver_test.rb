require "test_helper"

# Year resolution is the clearest case of "the model transcribes, code computes": the
# model read "Mi 19. August" correctly in all six evaluation runs and still resolved it
# to 2025 in two. The nearest occurrence decides; a printed weekday only checks it.
class EventCapture::YearResolverTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 8, 19) # a Wednesday

  def resolve(evidence, today: TODAY) = EventCapture::YearResolver.call(evidence, today: today)

  def conflict?(evidence, date) = EventCapture::YearResolver.weekday_conflict?(evidence, date)

  test "a bare date resolves to its nearest occurrence" do
    assert_equal Date.new(2026, 8, 19), resolve("Mi 19. August")
    assert_equal Date.new(2026, 8, 26), resolve("26.8.")
  end

  test "a recently-past date is a stale poster, not next year's show" do
    assert_equal Date.new(2026, 8, 8), resolve("Sa. 08.08.")
  end

  test "the past penalty still prefers a near past date across a year boundary" do
    assert_equal Date.new(2025, 12, 31), resolve("31.12.", today: Date.new(2026, 1, 5))
  end

  test "a year printed in the evidence is taken as given" do
    assert_equal Date.new(2025, 3, 20), resolve("Do 20. März 2025")
  end

  test "a textual month is read before a numeric pair" do
    assert_equal Date.new(2026, 8, 19), resolve("Mi 19. August 19.30h") # not day 19, month 30
  end

  test "French month tokens resolve" do
    assert_equal Date.new(2027, 3, 26), resolve("vendredi 26 mars")
  end

  test "evidence with no legible day and month resolves to nothing" do
    assert_nil resolve("Samstag")
    assert_nil resolve("")
    assert_nil resolve(nil)
  end

  test "an impossible day is not invented into a neighbouring one" do
    assert_nil resolve("30. Februar")
  end

  # The first digit pair on a poster line is regularly a time; stopping there threw
  # the date away and skipped the year check entirely.
  test "a leading time does not hide the date behind it" do
    assert_equal Date.new(2026, 12, 5), resolve("Doors 19.30 Uhr, Konzert am 5.12.")
  end


  test "a weekday agreeing with the resolved date raises nothing" do
    refute conflict?("Mi 19. August", Date.new(2026, 8, 19)) # a Wednesday
    refute conflict?("Sa 08.08. + So 09.08.", Date.new(2026, 8, 8))
    refute conflict?("So viel Musik, Fr 12. Juni", Date.new(2026, 6, 12))
  end

  test "a weekday contradicting the resolved date is reported, not obeyed" do
    assert_equal Date.new(2026, 8, 19), resolve("Di 19. August") # nearest still decides
    assert conflict?("Di 19. August", Date.new(2026, 8, 19))     # ...and the Tuesday is surfaced
  end

  # "die"/"mit" are a German article and preposition, "so" an adverb, and "mar" is both
  # mardi and an abbreviation of März. A spurious token costs only a false alarm now
  # that the weekday just raises a flag — but the flag is the signal, so keep it clean.
  test "ordinary prose raises no weekday conflict" do
    refute conflict?("Die Türen öffnen um 20 Uhr, 5. Mai", Date.new(2027, 5, 5))
    refute conflict?("3. Mar", Date.new(2027, 3, 3))
    refute conflict?("Mit dabei ... Sa 20.09.", Date.new(2025, 9, 20))
  end

  # English abbreviations are easy to leave out: "mon" looks covered already, being
  # short for Montag too.
  test "English abbreviations are recognised, like the German and French ones" do
    { "Sun 23 August" => 0, "Tue 25 August" => 2, "Wed 26 August" => 3,
      "Thu 27 August" => 4, "Fri 28 August" => 5, "Sat 29 August" => 6 }.each do |evidence, wday|
      date = resolve(evidence)

      assert_equal wday, date.wday, evidence
      refute conflict?(evidence, date), evidence
    end
  end
end
