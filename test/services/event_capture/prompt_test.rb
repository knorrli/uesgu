require "test_helper"

# Two properties of the prompt are load-bearing enough to pin. Everything else
# about it is tuning, and tuning is measured by the bake-off script, not asserted
# here.
class EventCapture::PromptTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 8, 19)

  # #99 renamed city → locality precisely because the prompt is a consumer of the
  # name: ask for a `city` and the model nulls out on a hamlet, which is the exact
  # field match-at-entry depends on.
  test "the contract asks for a locality and never for a city" do
    fields = EventCapture::Prompt::SCHEMA.dig(:schema, :properties, :events, :items, :required)

    assert_includes fields, "locality"
    refute_includes fields, "city"
    refute_match(/`city`/, EventCapture::Prompt.instructions(today: Date.new(2026, 8, 19)))
  end

  # Every date and place must be quotable, or null. This is most of the difference
  # between 0/6 and 5/6 fabricated dates, and it is what makes an uncited value
  # detectable as invention downstream.
  test "the evidence rule and today's date reach the model" do
    instructions = EventCapture::Prompt.instructions(today: Date.new(2026, 8, 19))

    assert_match "Today is 2026-08-19", instructions
    assert_match "date_evidence", instructions
    assert_match "place_evidence", instructions
  end

  # A prompt telling the model to read an image it was never sent is how a tuned
  # instruction turns into noise.
  test "each medium names only its own input" do
    image = EventCapture::Prompt.instructions(today: TODAY, medium: :image)
    text = EventCapture::Prompt.instructions(today: TODAY, medium: :text)

    assert_match(/from images/, image)
    assert_match(/read in the image/, image)

    assert_match(/from text/, text)
    refute_match(/image/i, text)
    refute_match(/screenshot/i, text)
    assert_match(/text below/, EventCapture::Prompt.request(medium: :text))
  end

  # The sentences the bake-off measured — most of the difference between 0/6 and 5/6
  # fabricated dates. Splitting the prompt by medium must not reword the tuned half.
  test "the tuned rules survive the medium split" do
    image = EventCapture::Prompt.instructions(today: TODAY).squish

    [
      "A plausible guess is worse than null",
      "ONE IMAGE MAY ADVERTISE SEVERAL EVENTS",
      "CHAT UI IS NOT EVENT DATA",
      "A \"Saturday\" divider tells you when the MESSAGE was sent",
      "The largest text on a poster is usually the ARTIST, not the venue",
      "Never substitute a venue you happen to know exists in that city",
      "Copy spelling exactly, including K vs C and umlauts",
      "Do not guess \"Bern\" because the image looks Swiss",
      "Do NOT roll a past date forward to next year"
    ].each { |sentence| assert_match sentence, image }
  end

  # Falling back to the image prompt would send poster instructions with pasted text
  # attached, which is worse than failing.
  test "an unknown medium raises rather than falling back" do
    assert_raises(KeyError) { EventCapture::Prompt.instructions(today: TODAY, medium: :pdf) }
  end
end
