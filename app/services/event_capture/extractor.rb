module EventCapture
  # One Input in, event candidates out. The whole extraction path in one call:
  # prompt the model, read its JSON, then hand every event it claims to the
  # Normalizer, which is where the deterministic fields are actually decided.
  #
  # An adapter's failure is already the shape this returns, so the funnel has one
  # error path: an unreadable upload and a provider outage look the same downstream.
  #
  # One input per call, deliberately. The verify screen fires N of these — one per
  # uploaded image, driven by the client — because 8 x 2.3s does not fit in one
  # request and there is no queue to reach for (the adapter is :inline and Solid
  # Queue was removed for competing with Puma for RAM). A failure is returned, not
  # raised, so a bad image is one row to retry rather than a dead batch.
  class Extractor
    Extraction = Data.define(:candidates, :model, :input_tokens, :output_tokens, :elapsed, :code, :error) do
      def initialize(candidates: [], model: nil, input_tokens: 0, output_tokens: 0, elapsed: 0.0, code: nil, error: nil)
        super
      end

      def ok? = error.nil?
    end

    def self.call(...) = new(...).call

    # The provider is resolved through a factory, and asked whether it is configured
    # rather than consulting EventCaptureConfig here, so a browser test can install a
    # canned client: extraction then runs on a Puma thread, where a block-scoped stub
    # is not reliably in force and where credentials may be absent anyway (CI holds
    # no master key).
    class << self
      attr_writer :client_factory

      def client_factory = @client_factory || -> { Infomaniak.new }
    end

    def initialize(input:, today: Time.zone.today, client: self.class.client_factory.call)
      @input = input
      @today = today
      @client = client
    end

    UNCONFIGURED = "extraction is not configured — set INFOMANIAK_API_TOKEN and INFOMANIAK_PRODUCT_ID"

    def call
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return Extraction.new(error: input.error, code: input.code) unless input.ok?
      return Extraction.new(error: UNCONFIGURED, code: :unconfigured) unless client.configured?

      response = client.call(input: input, today: today)
      events = Array(parse(response.text)["events"])

      Extraction.new(
        candidates: events.map { |event| Normalizer.call(event, today: today) },
        model: response.model,
        input_tokens: response.input_tokens,
        output_tokens: response.output_tokens,
        elapsed: since(started)
      )
    rescue ProviderError => e
      Extraction.new(error: e.message, code: :provider_error, elapsed: since(started))
    end

    private

    attr_reader :input, :today, :client

    def since(started) = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    # Structured output is requested, but a model that decides to wrap its JSON in
    # a markdown fence is not an error worth failing an upload over — take the
    # outermost object and move on. Anything less recoverable is a failed
    # extraction rather than zero events: "the poster had nothing on it" and "we
    # could not read the answer" must not look the same on the verify screen.
    def parse(text)
      body = text.to_s.sub(/\A\s*```(?:json)?/, "").sub(/```\s*\z/, "")
      first, last = body.index("{"), body.rindex("}")
      raise ProviderError, "no JSON object in response: #{text.to_s.truncate(300)}" unless first && last

      JSON.parse(body[first..last])
    rescue JSON::ParserError => e
      raise ProviderError, "unparseable JSON: #{e.message}"
    end
  end
end
