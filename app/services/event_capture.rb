# User event capture: turning a poster, a screenshot or a pasted page into event
# candidates a human then verifies. This namespace holds the extraction half —
# the prompt, the provider call, and the code-side validators that undo what a
# language model reliably gets wrong. Nothing here persists anything.
#
# Decisions, evidence and the provider bake-off: docs/user-event-capture-design.md.
module EventCapture
  # Anything that stopped us getting an answer out of the provider — transport,
  # HTTP status, or a body we could not read. Not raised past Extractor, which
  # turns it into a failed Extraction: one image failing is one row to retry, not
  # a dead batch.
  ProviderError = Class.new(StandardError)
end
