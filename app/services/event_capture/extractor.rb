module EventCapture
  # One Input in, event candidates out. The whole extraction path in one call:
  # prompt the model, read its JSON, then hand every event it claims to the
  # Normalizer, which is where the deterministic fields are actually decided.
  #
  # An adapter's failure is already the shape this returns, so the funnel has one
  # error path: an unreadable upload and a provider outage look the same downstream.
  #
  # One input per call, deliberately. The capture screen fires N of these — one per
  # uploaded image, driven by the client — because 8 x 2.3s does not fit in one
  # request and there is no queue to reach for (the adapter is :inline and Solid
  # Queue was removed for competing with Puma for RAM). A failure is returned, not
  # raised, so a bad image is one row to retry rather than a dead batch.
  class Extractor
    # `detail` is the payload-bearing half of a failure (see ProviderError) — it is
    # printed by the rake task and never persisted.
    Extraction = Data.define(:candidates, :medium, :model, :prompt_sha, :input_tokens,
                             :output_tokens, :elapsed, :code, :error, :detail, :attempt_token) do
      def initialize(candidates: [], medium: nil, model: nil, prompt_sha: nil, input_tokens: 0,
                     output_tokens: 0, elapsed: 0.0, code: nil, error: nil, detail: nil, attempt_token: nil)
        super
      end

      def ok? = error.nil?

      # What the Normalizer refused, as {"time_unparseable" => 2}. String keys: this
      # goes to a jsonb column, which would return them as strings anyway.
      def issue_counts = candidates.flat_map(&:issues).tally.transform_keys(&:to_s)
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

    # The recorded row rides back out on the Extraction: the verify screen puts it on
    # every card, so the corrections a human then makes attach to the read that
    # proposed them (see ExtractionFieldOutcome). Signed, because the card posts it
    # back — a raw id would let one contributor replace another's outcomes.
    def call
      extraction = extract
      extraction.with(attempt_token: record(extraction)&.capture_token)
    end

    private

    attr_reader :input, :today, :client

    def extract
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return Extraction.new(error: input.error, code: input.code) unless input.ok?
      return Extraction.new(medium: input.kind, error: UNCONFIGURED, code: :unconfigured) unless client.configured?

      response = client.call(input: input, today: today)
      events = Array(parse(response.text)["events"])
      # Once per response, not once per candidate: a poster advertising eight events
      # would otherwise re-query the taxonomy eight times.
      localities = Localities.known
      genres = Genres.known

      Extraction.new(
        candidates: events.map do |event|
          Normalizer.call(event, today: today, localities: localities, genres: genres)
        end,
        medium: input.kind,
        model: response.model,
        prompt_sha: Prompt.sha(medium: input.kind),
        input_tokens: response.input_tokens,
        output_tokens: response.output_tokens,
        elapsed: since(started)
      )
    rescue ProviderError => e
      Extraction.new(medium: input.kind, prompt_sha: Prompt.sha(medium: input.kind), error: e.message,
                     detail: e.detail, code: :provider_error, elapsed: since(started))
    end

    # Measuring the funnel may not break it: a contributor's upload is worth more
    # than the row that counts it.
    def record(extraction)
      ExtractionAttempt.record!(extraction)
    rescue StandardError => e
      Rails.logger.error("ExtractionAttempt.record! failed: #{e.class}: #{e.message}")
      nil
    end

    def since(started) = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    # Structured output is requested, but a model that decides to wrap its JSON in
    # a markdown fence is not an error worth failing an upload over — take the
    # outermost object and move on. Anything less recoverable is a failed
    # extraction rather than zero events: "the poster had nothing on it" and "we
    # could not read the answer" must not look the same on the capture screen.
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
