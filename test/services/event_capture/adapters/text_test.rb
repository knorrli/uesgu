require "test_helper"

class EventCapture::Adapters::TextTest < ActiveSupport::TestCase
  def call(text, **) = EventCapture::Adapters::Text.call(text, **)

  test "pasted text becomes a text input, and the pasted URL rides along" do
    input = call("  Zorpcore, Sa 22. August  ", source_url: "https://example.ch/e/1")

    assert_predicate input, :ok?
    assert_equal :text, input.kind
    assert_equal "Zorpcore, Sa 22. August", input.text
    assert_equal "https://example.ch/e/1", input.source_url
    refute_predicate input, :image?
  end

  test "nothing to read is a failure, not an extraction that finds no events" do
    assert_equal :text_empty, call("   \n ").code
    assert_equal :text_empty, call(nil).code
  end

  # A whole programme archive pasted by accident is truncated rather than sent:
  # the caller is a person watching a spinner.
  test "over-long input is truncated to the limit" do
    limit = EventCapture::Adapters::Text::LIMIT

    assert_equal limit, call("x" * (limit + 500)).text.length
    assert_equal limit, call("x" * limit).text.length
  end
end
