require "db_test_helper"

# The extraction path with the provider stubbed out. The contract: 0..n candidates on
# success, a failure RETURNED rather than raised (so one bad image is one row to
# retry), and one ExtractionAttempt written whichever of the two happened.
class EventCapture::ExtractorTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 8, 19)

  # Stands in for EventCapture::Infomaniak: answers with canned provider text, or
  # raises the way the real client does.
  class FakeClient
    attr_reader :calls

    def initialize(text: nil, raises: nil, detail: nil, configured: true)
      @text = text
      @raises = raises
      @detail = detail
      @configured = configured
      @calls = []
    end

    def configured? = @configured

    def call(**args)
      @calls << args
      raise EventCapture::ProviderError.new(@raises, detail: @detail) if @raises

      EventCapture::Infomaniak::Response.new(text: @text, model: "google/gemma-4-31B-it",
                                             input_tokens: 1200, output_tokens: 90)
    end
  end

  def extract(client)
    EventCapture::Extractor.call(input: EventCapture::Input.image("PNG-ish", media_type: "image/png"),
                                 today: TODAY, client: client)
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

  # The Extractor is the only thing that hands the Normalizer the taxonomy to read,
  # so it is the only place the wiring can break.
  test "candidates are placed against the localities the taxonomy already carries" do
    place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")

    extraction = extract(FakeClient.new(text: payload(
      { title: "Zorpcore Nacht", locality: "zorpwil", locality_evidence: "3000 Zorpwil", canton: nil }
    )))

    assert_equal "BE", extraction.candidates.sole.canton
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
    client = FakeClient.new(text: payload, configured: false)

    extraction = EventCapture::Extractor.call(input: EventCapture::Input.image("x", media_type: "image/png"),
                                              client: client)

    refute_predicate extraction, :ok?
    assert_match(/INFOMANIAK_API_TOKEN/, extraction.error)
    assert_empty client.calls
  end

  test "a failed input is returned as a failed extraction, unsent" do
    client = FakeClient.new(text: payload)
    input = EventCapture::Input.failure(:image_unsupported, "not a PNG, JPEG, WebP or GIF")

    extraction = EventCapture::Extractor.call(input: input, client: client)

    refute_predicate extraction, :ok?
    assert_equal :image_unsupported, extraction.code
    assert_empty client.calls
  end

  test "a successful extraction is recorded with its cost and everything the Normalizer refused" do
    extract(FakeClient.new(text: payload(
      { title: "Zorpcore Nacht", date: "2026-08-20", date_evidence: "20. August", time: "kurz nach acht" },
      { title: "Zorpwave Matinee", date: "2026-08-21", date_evidence: "21. August", time: "am Abend" }
    )))

    attempt = ExtractionAttempt.sole
    assert_predicate attempt, :ok?
    assert_equal "image", attempt.medium
    assert_equal "google/gemma-4-31B-it", attempt.model
    assert_equal EventCapture::Prompt.sha(medium: :image), attempt.prompt_sha
    assert_equal 2, attempt.candidates_count
    assert_equal 1200, attempt.input_tokens
    assert_equal 90, attempt.output_tokens
    assert_equal 2, attempt.issues["time_unparseable"]
  end

  # The whole point of separating ProviderError's message from its detail: a
  # screenshot's model output can name the person who sent it.
  test "a failed attempt records the code and the neutral message, never the provider payload" do
    extraction = extract(FakeClient.new(raises: "HTTP 503", detail: "upstream busy — from Zorp Zorpsson, +41 79 000 00 00"))

    attempt = ExtractionAttempt.sole
    assert_predicate attempt, :failed?
    assert_equal "provider_error", attempt.code
    assert_equal "HTTP 503", attempt.error_message
    assert_equal EventCapture::Prompt.sha(medium: :image), attempt.prompt_sha
    assert_match(/Zorpsson/, extraction.detail)
    refute_match(/Zorpsson/, ExtractionAttempt.pluck(:error_message).join(" "))
  end

  test "an input that never reached the provider is recorded too" do
    EventCapture::Extractor.call(input: EventCapture::Input.failure(:image_unsupported, "not a PNG, JPEG, WebP or GIF"),
                                 client: FakeClient.new(text: payload))

    attempt = ExtractionAttempt.sole
    assert_predicate attempt, :failed?
    assert_equal "image_unsupported", attempt.code
    assert_nil attempt.prompt_sha
  end

  test "a recording failure does not fail the capture" do
    ExtractionAttempt.stub(:record!, ->(*) { raise ActiveRecord::StatementInvalid, "no such table" }) do
      extraction = extract(FakeClient.new(text: payload({ title: "Zorpcore" })))

      assert_predicate extraction, :ok?
      assert_equal ["Zorpcore"], extraction.candidates.map(&:title)
    end
  end
end
