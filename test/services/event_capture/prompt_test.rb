require "test_helper"

# Two properties of the prompt are load-bearing enough to pin. Everything else
# about it is tuning, and tuning is measured by the bake-off script, not asserted
# here.
class EventCapture::PromptTest < ActiveSupport::TestCase
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
end
