require "test_helper"

# The provider call, with the socket stubbed. Asserts the request we actually put
# on the wire — Infomaniak's product-scoped OpenAI route, the image inlined as a
# data URL, strict structured output — and that every transport failure surfaces
# as one ProviderError for the Extractor to turn into a retryable row.
class EventCapture::InfomaniakTest < ActiveSupport::TestCase
  class FakeHTTP
    attr_accessor :use_ssl, :open_timeout, :read_timeout
    attr_reader :posted

    def initialize(response) = @response = response

    def request(req)
      @posted = req
      raise @response if @response.is_a?(StandardError)

      @response
    end
  end

  def response(code, body)
    klass = code == "200" ? Net::HTTPOK : Net::HTTPServiceUnavailable
    klass.new("1.1", code, "").tap do |res|
      res.instance_variable_set(:@body, body)
      res.instance_variable_set(:@read, true)
    end
  end

  def call_with(canned, input: EventCapture::Input.image("PNGDATA", media_type: "image/png"))
    http = FakeHTTP.new(canned)
    result = EventCaptureConfig.stub(:api_token, "tok-123") do
      EventCaptureConfig.stub(:product_id, "4242") do
        Net::HTTP.stub(:new, http) do
          yield_result { EventCapture::Infomaniak.new.call(input: input, today: Date.new(2026, 8, 19)) }
        end
      end
    end
    [result, http.posted]
  end

  def yield_result
    yield
  rescue EventCapture::ProviderError => e
    e
  end

  test "posts the image to the product-scoped route with the model and schema" do
    result, request = call_with(response("200", JSON.generate(
      choices: [{ message: { content: '{"events":[]}' } }],
      model: "google/gemma-4-31B-it", usage: { prompt_tokens: 1200, completion_tokens: 90 }
    )))

    assert_equal "/2/ai/4242/openai/v1/chat/completions", request.path
    assert_equal "Bearer tok-123", request["authorization"]

    body = JSON.parse(request.body)
    assert_equal EventCaptureConfig.model, body["model"]
    assert_equal "json_schema", body.dig("response_format", "type")
    assert_equal "data:image/png;base64,#{Base64.strict_encode64('PNGDATA')}",
                 body.dig("messages", 1, "content", 1, "image_url", "url")

    assert_equal '{"events":[]}', result.text
    assert_equal 1200, result.input_tokens
  end

  # The status is the message because that message is persisted on every failed
  # attempt; the body it came with is a payload and stays in `detail`.
  test "a non-200 becomes a ProviderError carrying the status, with the body kept out of the message" do
    result, = call_with(response("503", "upstream busy"))

    assert_kind_of EventCapture::ProviderError, result
    assert_equal "HTTP 503", result.message
    assert_equal "upstream busy", result.detail
  end

  # The product id is interpolated into the request path, so a malformed one has to
  # fail like any other bad configuration — Extractor rescues ProviderError only, and
  # anything else reaches the capture screen as a 500 instead of one retryable row.
  test "a malformed product id becomes a ProviderError, not a raw exception" do
    result = EventCaptureConfig.stub(:api_token, "tok-123") do
      EventCaptureConfig.stub(:product_id, "42 42") do
        yield_result { EventCapture::Infomaniak.new.call(input: EventCapture::Input.image("x", media_type: "image/png"), today: Date.new(2026, 8, 19)) }
      end
    end

    assert_kind_of EventCapture::ProviderError, result
  end

  test "a transport failure becomes a ProviderError too" do
    result, = call_with(Net::OpenTimeout.new("execution expired"))

    assert_kind_of EventCapture::ProviderError, result
    assert_match(/Net::OpenTimeout/, result.message)
  end
end
