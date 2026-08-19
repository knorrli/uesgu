require "test_helper"

class EventCapture::Adapters::TextTest < ActiveSupport::TestCase
  def call(text) = EventCapture::Adapters::Text.call(text)

  test "pasted text becomes a text input" do
    input = call("  Zorpcore, Sa 22. August  ")

    assert_predicate input, :ok?
    assert_equal :text, input.kind
    assert_equal "Zorpcore, Sa 22. August", input.text
    refute_predicate input, :image?
  end

  test "binary-encoded input is scrubbed to UTF-8 rather than reaching the provider call" do
    input = call("Café Kairo, Sa 22. August".dup.force_encoding(Encoding::ASCII_8BIT))

    assert_equal Encoding::UTF_8, input.text.encoding
    assert_equal "Café Kairo, Sa 22. August", input.text
    assert_nothing_raised { JSON.generate(text: input.text) }
  end

  test "bytes that are not valid UTF-8 are replaced, not raised on" do
    input = call("Caf\xE9 Kairo".dup.force_encoding(Encoding::ASCII_8BIT))

    assert_predicate input.text, :valid_encoding?
    assert_nothing_raised { JSON.generate(text: input.text) }
  end

  test "nothing to read is a failure, not an extraction that finds no events" do
    assert_equal :text_empty, call("   \n ").code
    assert_equal :text_empty, call(nil).code
  end

  test "over-long input is truncated to the limit" do
    limit = EventCapture::Adapters::Text::LIMIT

    assert_equal limit, call("x" * (limit + 500)).text.length
    assert_equal limit, call("x" * limit).text.length
  end
end
