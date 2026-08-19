module EventCapture
  # The provider call. Infomaniak's AI tools speak an OpenAI-shaped API under a
  # product-scoped path, so the body below is the ordinary chat-completions
  # shape: an image is inlined as a data URL, while pasted or fetched text rides
  # in a second text part.
  #
  # Swiss-hosted, and chosen on accuracy rather than price: 0/6 fabricated dates
  # against Mistral Small 4's 5/6, at ~6 cents a month either way (see "Provider
  # evaluation" in docs/user-event-capture-design.md). Net::HTTP rather than
  # Mechanize — that agent exists for scraping HTML with robots enforcement, and
  # none of it applies to a JSON API we hold an account with.
  class Infomaniak
    Response = Data.define(:text, :model, :input_tokens, :output_tokens)

    # 2.3s is the measured round trip. The read timeout is generous against a slow
    # day but still bounded, because the caller is a person watching a spinner.
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 60
    MAX_TOKENS = 4000

    def call(input:, today:)
      response = post(request_body(input, today))

      Response.new(
        text: response.dig("choices", 0, "message", "content"),
        model: response["model"] || EventCaptureConfig.model,
        input_tokens: response.dig("usage", "prompt_tokens").to_i,
        output_tokens: response.dig("usage", "completion_tokens").to_i
      )
    end

    private

    def endpoint
      URI("https://api.infomaniak.com/2/ai/#{EventCaptureConfig.product_id}/openai/v1/chat/completions")
    end

    def request_body(input, today)
      {
        model: EventCaptureConfig.model,
        max_tokens: MAX_TOKENS,
        # Structured output, strict: Infomaniak rejects the older `json_object`
        # mode outright, and strict mode forces every field to be present so an
        # omitted `date` cannot read as a considered null.
        response_format: { type: "json_schema", json_schema: Prompt::SCHEMA },
        messages: [
          { role: "system", content: Prompt.instructions(today: today, medium: input.kind) },
          { role: "user", content: content_for(input) }
        ]
      }
    end

    def content_for(input)
      return [request_part(input), text_part(input)] unless input.image?

      [request_part(input),
       { type: "image_url",
         image_url: { url: "data:#{input.media_type};base64,#{Base64.strict_encode64(input.image_data)}" } }]
    end

    def request_part(input) = { type: "text", text: Prompt.request(medium: input.kind) }

    # Fenced, because a fetched page is untrusted text arriving in the same channel
    # as the instructions. The fence is not a security boundary — nothing stops a
    # page from writing one — but it is what makes "everything after this line is
    # data" a claim the model can act on at all, and the rules it would have to
    # overturn live in the system message above.
    def text_part(input)
      { type: "text", text: "<<<INPUT\n#{input.text}\nINPUT" }
    end

    def post(body)
      uri = endpoint
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri)
      request["authorization"] = "Bearer #{EventCaptureConfig.api_token}"
      request["content-type"] = "application/json"
      request.body = JSON.generate(body)

      response = http.request(request)
      raise ProviderError, "HTTP #{response.code}: #{response.body.to_s.truncate(300)}" unless response.is_a?(Net::HTTPOK)

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise ProviderError, "unreadable response: #{e.message}"
    # URI::InvalidURIError belongs here too: the product id is interpolated into the
    # path, so a malformed one must fail like any other bad configuration rather
    # than escape Extractor's rescue as a 500 on the verify screen.
    rescue Timeout::Error, IOError, SystemCallError, SocketError, Net::HTTPBadResponse,
           OpenSSL::SSL::SSLError, URI::InvalidURIError => e
      raise ProviderError, "#{e.class}: #{e.message}"
    end
  end
end
