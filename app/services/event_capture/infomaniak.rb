module EventCapture
  class Infomaniak
    Response = Data.define(:text, :model, :input_tokens, :output_tokens)

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 60

    MAX_TOKENS = 4000

    TOKEN_CEILING_REACHED = "length"

    def configured? = EventCaptureConfig.configured?

    def call(input:, today:, correction: nil)
      response = post(request_body(input, today, correction))
      completion_tokens = response.dig("usage", "completion_tokens").to_i
      raise_truncated(completion_tokens) if response.dig("choices", 0, "finish_reason") == TOKEN_CEILING_REACHED

      Response.new(
        text: response.dig("choices", 0, "message", "content"),
        model: response["model"] || EventCaptureConfig.model,
        input_tokens: response.dig("usage", "prompt_tokens").to_i,
        output_tokens: completion_tokens
      )
    end

    private

    def raise_truncated(completion_tokens)
      raise TruncatedResponse.new("truncated at max_tokens (#{MAX_TOKENS})",
                                  detail: "completion_tokens=#{completion_tokens}")
    end

    def endpoint
      URI("https://api.infomaniak.com/2/ai/#{EventCaptureConfig.product_id}/openai/v1/chat/completions")
    end

    def request_body(input, today, correction)
      {
        model: EventCaptureConfig.model,
        max_tokens: MAX_TOKENS,
        response_format: { type: "json_schema", json_schema: Prompt::SCHEMA },
        messages: [
          { role: "system",
            content: Prompt.instructions(today: today, medium: input.kind, correction: correction) },
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
      unless response.is_a?(Net::HTTPOK)
        raise ProviderError.new("HTTP #{response.code}", detail: response.body.to_s.truncate(300))
      end

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise ProviderError.new("unreadable response", detail: e.message)
    rescue Timeout::Error, IOError, SystemCallError, SocketError, Net::HTTPBadResponse,
           OpenSSL::SSL::SSLError, URI::InvalidURIError => e
      raise ProviderError, "#{e.class}: #{e.message}"
    end
  end
end
