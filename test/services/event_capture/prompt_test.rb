require "test_helper"

# Only the properties the extraction breaks without are pinned here. The rest of the
# prompt is tuning, measured by script/event_capture_bakeoff.rb rather than asserted.
class EventCapture::PromptTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 8, 19)

  # See EventCapture::Prompt for why the field cannot be `city`.
  test "the contract asks for a locality and never for a city" do
    fields = EventCapture::Prompt::SCHEMA.dig(:schema, :properties, :events, :items, :required)

    assert_includes fields, "locality"
    refute_includes fields, "city"
    refute_match(/`city`/, EventCapture::Prompt.instructions(today: Date.new(2026, 8, 19)))
  end

  # An uncited value is what Normalizer#cited later reads as invention, so the rule
  # reaching the model is what makes that detection mean anything.
  test "the evidence rule and today's date reach the model" do
    instructions = EventCapture::Prompt.instructions(today: Date.new(2026, 8, 19))

    assert_match "Today is 2026-08-19", instructions
    assert_match "date_evidence", instructions
    assert_match "place_evidence", instructions
    assert_match "locality_evidence", instructions
  end

  # Normalizer#cited reads a value whose evidence field is empty as invention, so a
  # cited field missing its evidence property would null every value the model returns.
  test "every field the evidence rule governs has an evidence field in the contract" do
    fields = EventCapture::Prompt::SCHEMA.dig(:schema, :properties, :events, :items, :required)

    %w[date place locality].each { |field| assert_includes fields, "#{field}_evidence" }
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

  # These exact sentences are the measured half of the prompt: reworded, the model
  # fabricates dates again (see EventCapture::Prompt).
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

  # The sha is what attributes a change in the recorded numbers to a prompt edit, so
  # it must move only when the wording does — hashing the rendered prompt would
  # remint it every night, because the date is interpolated into it.
  test "the prompt sha ignores the date and separates the media" do
    image = travel_to(Time.zone.local(2026, 1, 1)) { EventCapture::Prompt.sha }
    a_year_later = travel_to(Time.zone.local(2027, 6, 30)) { EventCapture::Prompt.sha }

    assert_equal image, a_year_later
    refute_equal image, EventCapture::Prompt.sha(medium: :text)
  end
end
