require "test_helper"

# The media type is sniffed rather than trusted, so these are the bytes a real
# upload starts with.
class EventCapture::Adapters::ImageTest < ActiveSupport::TestCase
  PNG = "\x89PNG\r\n\x1A\n".b + ("\0" * 32)
  JPEG = "\xFF\xD8\xFF\xE0".b + ("\0" * 32)
  GIF = "GIF89a".b + ("\0" * 32)
  WEBP = "RIFF".b + "\x24\0\0\0".b + "WEBP".b + ("\0" * 16)
  HEIC = "\0\0\0\x18".b + "ftyp".b + "heic".b + ("\0" * 16)

  def call(data) = EventCapture::Adapters::Image.call(data)

  test "each supported format is recognised from its magic bytes" do
    { PNG => "image/png", JPEG => "image/jpeg", GIF => "image/gif", WEBP => "image/webp" }
      .each do |data, media_type|
        input = call(data)

        assert_predicate input, :ok?
        assert_predicate input, :image?
        assert_equal media_type, input.media_type
        assert_equal data, input.image_data
      end
  end

  # "RIFF" alone is also AVI and WAV.
  test "a RIFF container that is not WebP is not accepted as one" do
    input = call("RIFF".b + "\x24\0\0\0".b + "AVI ".b + ("\0" * 16))

    refute_predicate input, :ok?
    assert_equal :image_unsupported, input.code
  end

  test "HEIC is refused by name, with the fix in the message" do
    input = call(HEIC)

    assert_equal :image_unsupported, input.code
    assert_match(/HEIC/, input.error)
    assert_match(/JPEG/, input.error)
  end

  test "empty and oversized inputs are refused before anything is sent" do
    assert_equal :image_empty, call("").code
    assert_equal :image_too_large, call(PNG + ("x" * EventCapture::Adapters::Image::LIMIT)).code
  end

  test "a PDF or a text file is refused rather than sent to a model that cannot read it" do
    assert_equal :image_unsupported, call("%PDF-1.7\n").code
    assert_equal :image_unsupported, call("Zorpcore, Sa 22. August").code
  end
end
