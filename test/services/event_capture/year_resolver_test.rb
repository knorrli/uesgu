require "test_helper"

# Year resolution is the clearest case of "the model transcribes, code computes":
# the bake-off model read "Mi 19. August" correctly in all six runs and still
# resolved it to 2025 in two of them. These are the nine cases from the design doc.
class EventCapture::YearResolverTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 8, 19) # a Wednesday

  def resolve(evidence, today: TODAY) = EventCapture::YearResolver.call(evidence, today: today)

  test "a printed weekday picks the year, even against the model's own answer" do
    assert_equal Date.new(2026, 8, 19), resolve("Mi 19. August") # 19 Aug 2025 is a Tuesday
  end

  test "the weekday checksum can select a year in the past" do
    assert_equal Date.new(2025, 8, 19), resolve("Di 19. August")
  end

  test "without a weekday, the nearest occurrence wins" do
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

  test "French weekday and month tokens resolve" do
    assert_equal Date.new(2027, 3, 26), resolve("vendredi 26 mars") # 26 Mar 2027 is a Friday
  end

  test "evidence with no legible day and month resolves to nothing" do
    assert_nil resolve("Samstag")
    assert_nil resolve("")
    assert_nil resolve(nil)
  end

  test "an impossible day is not invented into a neighbouring one" do
    assert_nil resolve("30. Februar")
  end
end
