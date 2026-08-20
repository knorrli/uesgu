# One row per EventCapture::Extractor#call: what the provider was asked, what it
# cost, and which values the Normalizer refused. Metadata only — no field values,
# no image, and an error message with its payload stripped (see
# EventCapture::ProviderError) — so nothing here ages out and `prune!` is only a
# size backstop.
#
# Two questions it answers that logs cannot: is the provider erroring right now,
# and is a given `issues` code trending against a prompt edit. That second one is
# why every row carries the model AND the prompt sha: prompt tuning was measured
# not to transfer between models (docs/user-event-capture-design.md).
class ExtractionAttempt < ApplicationRecord
  enum :status, { ok: "ok", failed: "failed" }

  scope :recent, -> { order(created_at: :desc) }

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
