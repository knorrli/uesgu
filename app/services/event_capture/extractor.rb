module EventCapture
  # Image in, event candidates out. The whole extraction path in one call: prompt
  # the model, read its JSON, then hand every event it claims to the Normalizer,
  # which is where the deterministic fields are actually decided.
  #
  # One image per call, deliberately. The verify screen fires N of these — one per
  # uploaded image, driven by the client — because 8 x 2.3s does not fit in one
  # request and there is no queue to reach for (the adapter is :inline and Solid
  # Queue was removed for competing with Puma for RAM). A failure is returned, not
  # raised, so a bad image is one row to retry rather than a dead batch.
  class Extractor
    Extraction = Data.define(:candidates, :model, :input_tokens, :output_tokens, :elapsed, :error) do
      def initialize(candidates: [], model: nil, input_tokens: 0, output_tokens: 0, elapsed: 0.0, error: nil)
        super
      end

      def ok? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(image_data:, media_type:, today: Time.zone.today, client: Infomaniak.new)
      @image_data = image_data
      @media_type = media_type
      @today = today
      @client = client
    end

    UNCONFIGURED = "extraction is not configured — set INFOMANIAK_API_TOKEN and INFOMANIAK_PRODUCT_ID"

    def call
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return Extraction.new(error: UNCONFIGURED) unless EventCaptureConfig.configured?

      response = client.call(image_data: image_data, media_type: media_type, today: today)
      events = Array(parse(response.text)["events"])

      Extraction.new(
        candidates: events.map { |event| Normalizer.call(event, today: today) },
        model: response.model,
        input_tokens: response.input_tokens,
        output_tokens: response.output_tokens,
        elapsed: since(started)
      )
    rescue ProviderError => e
      Extraction.new(error: e.message, elapsed: since(started))
    end

    private

    attr_reader :image_data, :media_type, :today, :client

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
