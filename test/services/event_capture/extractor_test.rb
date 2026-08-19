require "test_helper"

# The extraction path with the provider stubbed out. What matters here is the
# contract the verify screen will be written against: 0..n candidates on success,
# and a failure that is RETURNED rather than raised, so one bad image is one row
# to retry.
class EventCapture::ExtractorTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 8, 19)

  # Stands in for EventCapture::Infomaniak: answers with canned provider text, or
  # raises the way the real client does.
  class FakeClient
    attr_reader :calls

    def initialize(text: nil, raises: nil)
      @text = text
      @raises = raises
      @calls = []
    end

    def call(**args)
      @calls << args
      raise EventCapture::ProviderError, @raises if @raises

      EventCapture::Infomaniak::Response.new(text: @text, model: "google/gemma-4-31B-it",
                                             input_tokens: 1200, output_tokens: 90)
    end
  end

  def extract(client)
    EventCaptureConfig.stub(:configured?, true) do
      EventCapture::Extractor.call(input: EventCapture::Input.image("PNG-ish", media_type: "image/png"),
                                   today: TODAY, client: client)
    end
  end

  def payload(*events) = JSON.generate({ events: events })

  test "one image can yield several events, each normalised" do
    extraction = extract(FakeClient.new(text: payload(
      { title: "Zorpcore Nacht", date: "2026-08-20", date_evidence: "Do 20. August", time: "20 Uhr" },
      { title: "Zorpwave Matinee", date: "2026-08-21", date_evidence: "Fr 21. August" }
    )))

    assert_predicate extraction, :ok?
    assert_equal ["Zorpcore Nacht", "Zorpwave Matinee"], extraction.candidates.map(&:title)
    assert_equal "20:00", extraction.candidates.first.time
    assert_equal "google/gemma-4-31B-it", extraction.model
    assert_equal 1200, extraction.input_tokens
  end

  test "an image advertising nothing is zero candidates, not a failure" do
    extraction = extract(FakeClient.new(text: payload))

    assert_predicate extraction, :ok?
    assert_empty extraction.candidates
  end

  test "a fenced answer is unwrapped rather than failed" do
    extraction = extract(FakeClient.new(text: "```json\n#{payload({ title: "Zorpcore" })}\n```"))

    assert_equal ["Zorpcore"], extraction.candidates.map(&:title)
  end

  test "an unreadable answer fails the extraction instead of reading as zero events" do
    extraction = extract(FakeClient.new(text: "I could not see any events, sorry!"))

    refute_predicate extraction, :ok?
    assert_match(/no JSON object/, extraction.error)
    assert_empty extraction.candidates
  end

  test "a provider failure is returned, not raised" do
    extraction = extract(FakeClient.new(raises: "HTTP 503: upstream busy"))

    refute_predicate extraction, :ok?
    assert_equal "HTTP 503: upstream busy", extraction.error
  end

  test "without credentials nothing is sent and the reason says which ones" do
    client = FakeClient.new(text: payload)

    extraction = EventCaptureConfig.stub(:configured?, false) do
      EventCapture::Extractor.call(input: EventCapture::Input.image("x", media_type: "image/png"), client: client)
    end

    refute_predicate extraction, :ok?
    assert_match(/INFOMANIAK_API_TOKEN/, extraction.error)
    assert_empty client.calls
  end

  test "a failed input is returned as a failed extraction, unsent" do
    client = FakeClient.new(text: payload)
    input = EventCapture::Input.failure(:image_unsupported, "not a PNG, JPEG, WebP or GIF")

    extraction = EventCaptureConfig.stub(:configured?, true) do
      EventCapture::Extractor.call(input: input, client: client)
    end

    refute_predicate extraction, :ok?
    assert_equal :image_unsupported, extraction.code
    assert_empty client.calls
  end
end
