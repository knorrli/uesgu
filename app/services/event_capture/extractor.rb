module EventCapture
  class Extractor
    Extraction = Data.define(:candidates, :medium, :model, :prompt_sha, :input_tokens,
                             :output_tokens, :elapsed, :code, :error, :detail, :attempt_token) do
      def initialize(candidates: [], medium: nil, model: nil, prompt_sha: nil, input_tokens: 0,
                     output_tokens: 0, elapsed: 0.0, code: nil, error: nil, detail: nil, attempt_token: nil)
        super
      end

      def ok? = error.nil?

      def issue_counts = candidates.flat_map(&:issues).tally.transform_keys(&:to_s)
    end

    def self.call(...) = new(...).call

    class << self
      attr_writer :client_factory

      def client_factory = @client_factory || -> { Infomaniak.new }
    end

    def initialize(input:, today: Time.zone.today, correction: nil, client: self.class.client_factory.call)
      @input = input
      @today = today
      @correction = correction
      @client = client
    end

    UNCONFIGURED = "extraction is not configured — set INFOMANIAK_API_TOKEN and INFOMANIAK_PRODUCT_ID"

    def call
      extraction = extract
      extraction.with(attempt_token: record(extraction)&.capture_token)
    end

    private

    attr_reader :input, :today, :correction, :client

    def extract
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return Extraction.new(error: input.error, code: input.code) unless input.ok?
      return Extraction.new(medium: input.kind, error: UNCONFIGURED, code: :unconfigured) unless client.configured?

      response = client.call(input: input, today: today, correction: correction)
      events = Array(parse(response.text)["events"])
      genres = Genres.known

      Extraction.new(
        candidates: events.map { |event| Normalizer.call(event, today: today, genres: genres) },
        medium: input.kind,
        model: response.model,
        prompt_sha: Prompt.sha(medium: input.kind),
        input_tokens: response.input_tokens,
        output_tokens: response.output_tokens,
        elapsed: since(started)
      )
    rescue TruncatedResponse => e
      failed(e, code: :truncated, started: started)
    rescue ProviderError => e
      failed(e, code: :provider_error, started: started)
    end

    def failed(error, code:, started:)
      Extraction.new(medium: input.kind, prompt_sha: Prompt.sha(medium: input.kind), error: error.message,
                     detail: error.detail, code: code, elapsed: since(started))
    end

    def record(extraction)
      ExtractionAttempt.record!(extraction)
    rescue StandardError => e
      Rails.logger.error("ExtractionAttempt.record! failed: #{e.class}: #{e.message}")
      nil
    end

    def since(started) = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    def parse(text)
      body = text.to_s.sub(/\A\s*```(?:json)?/, "").sub(/```\s*\z/, "")
      first, last = body.index("{"), body.rindex("}")
      raise ProviderError.new("no JSON object in response", detail: text.to_s.truncate(300)) unless first && last

      JSON.parse(body[first..last])
    rescue JSON::ParserError => e
      raise ProviderError.new("unparseable JSON", detail: e.message)
    end
  end
end
