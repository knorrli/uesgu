module EventCapture
  module Adapters
    module Text
      LIMIT = 20_000

      module_function

      def call(text)
        text = scrubbed(text)
        return Input.failure(:text_empty, "no text to extract from") if text.blank?

        Input.text(truncated(text))
      end

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
