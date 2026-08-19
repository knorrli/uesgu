module EventCapture
  module Adapters
    # Pasted text: a chat message, a copied programme listing, a transcription. The
    # plainest of the three — the model reads what it is given, and rule 2 of the
    # prompt (chat chrome is not event data) already covers the messy case.
    module Text
      # Far past any poster or chat message, and short enough that a whole
      # programme archive pasted by accident is truncated rather than sent. The
      # extraction is one interactive request someone is watching, so an input that
      # would take a minute to read is the wrong thing to be polite about.
      LIMIT = 20_000

      module_function

      def call(text)
        text = scrubbed(text)
        return Input.failure(:text_empty, "no text to extract from") if text.blank?

        Input.text(truncated(text))
      end

      # A paste arrives as UTF-8, but a file read off disk arrives as ASCII-8BIT and
      # any byte over 0x7F in it makes JSON.generate raise in the provider call —
      # neither a JSON::ParserError nor a ProviderError, so it would escape both
      # rescues as a 500 rather than the returned failure this whole path rests on.
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
