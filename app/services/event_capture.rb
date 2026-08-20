# User event capture: turning a poster, a screenshot or pasted text into event
# candidates a human then verifies. This namespace holds the extraction half —
# the prompt, the provider call, and the code-side validators that undo what a
# language model reliably gets wrong. The only thing persisted is one
# ExtractionAttempt per call: metadata, never a field value.
#
# Decisions, evidence and the provider bake-off: docs/user-event-capture-design.md.
module EventCapture
  # Anything that stopped us getting an answer out of the provider — transport,
  # HTTP status, or a body we could not read. Not raised past Extractor, which
  # turns it into a failed Extraction: one image failing is one row to retry, not
  # a dead batch.
  #
  # `message` is deliberately the neutral half, because it is persisted on every
  # failed attempt. Whatever quotes the provider's answer — a response body, a
  # fragment of model output — goes in `detail`, which stays in memory: a
  # WhatsApp screenshot's model output can carry the sender's name or number, and
  # storing that would reintroduce exactly what discarding the image prevents.
  class ProviderError < StandardError
    attr_reader :detail

    def initialize(message, detail: nil)
      super(message)
      @detail = detail
    end
  end
end
