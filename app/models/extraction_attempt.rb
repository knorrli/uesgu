# One row per EventCapture::Extractor#call: what the provider was asked, what it
# cost, and which values the Normalizer refused. Metadata only — no field values,
# no image, and an error message with its payload stripped (see
# EventCapture::ProviderError) — so nothing in this table ages out and `prune!` is
# only a size backstop. The field outcomes hanging off it do carry values, and go
# when the row does.
#
# Two questions it answers that logs cannot: is the provider erroring right now,
# and is a given `issues` code trending against a prompt edit. That second one is
# why every row carries the model AND the prompt sha: prompt tuning was measured
# not to transfer between models (docs/user-event-capture-provider-evaluation.md).
class ExtractionAttempt < ApplicationRecord
  # The FK cascades in the database, which is what keeps `prune!` a single statement.
  has_many :field_outcomes, class_name: "ExtractionFieldOutcome", dependent: :delete_all,
           inverse_of: :extraction_attempt

  enum :status, { ok: "ok", failed: "failed" }

  scope :recent, -> { order(created_at: :desc) }

  # What the verify screen carries so a correction can name the read that proposed
  # it. Signed and short-lived: the card posts it back, and an id a contributor
  # could type would let them replace someone else's outcomes.
  TOKEN_PURPOSE = :capture
  TOKEN_TTL = 1.day

  def capture_token = signed_id(purpose: TOKEN_PURPOSE, expires_in: TOKEN_TTL)

  def self.find_by_capture_token(token) = find_signed(token, purpose: TOKEN_PURPOSE)

  KEEP = 2000
  def self.prune!(keep: KEEP)
    keep_ids = recent.limit(keep).pluck(:id)
    where.not(id: keep_ids).delete_all if keep_ids.any?
  end

  def self.record!(extraction)
    create!(
      status: extraction.ok? ? :ok : :failed,
      code: extraction.code,
      medium: extraction.medium,
      model: extraction.model,
      prompt_sha: extraction.prompt_sha,
      candidates_count: extraction.candidates.size,
      input_tokens: extraction.input_tokens,
      output_tokens: extraction.output_tokens,
      duration_ms: (extraction.elapsed * 1000).round,
      issues: extraction.issue_counts,
      error_message: extraction.error
    )
  end
end
