module EventCapture
  module Adapters
    # Chat chrome is not stripped here — prompt rule 2 makes the model ignore it, and
    # a screenshot of the same message gets no such help from us either.
    module Text
      # The extraction is one request someone is watching, so a programme archive
      # pasted by accident is truncated rather than sent.
      LIMIT = 20_000

      module_function

      def call(text)
        text = scrubbed(text)
        return Input.failure(:text_empty, "no text to extract from") if text.blank?

        Input.text(truncated(text))
      end

      # A file read off disk arrives ASCII-8BIT, and any byte over 0x7F in it makes
      # JSON.generate raise inside the provider call — neither a JSON::ParserError
      # nor a ProviderError, so it escapes both rescues instead of coming back as one
      # failed row.
      def scrubbed(text)
        text.to_s.dup.force_encoding(Encoding::UTF_8).scrub.strip
      end

      def truncated(text)
        return text if text.length <= LIMIT

        Rails.logger.warn("[EventCapture] input truncated to #{LIMIT} of #{text.length} characters")
        text[0, LIMIT]
      end
    end
  end
end
