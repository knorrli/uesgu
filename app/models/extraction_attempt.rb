class ExtractionAttempt < ApplicationRecord
  has_many :field_outcomes, class_name: "ExtractionFieldOutcome", dependent: :delete_all,
           inverse_of: :extraction_attempt

  enum :status, { ok: "ok", failed: "failed" }

  scope :recent, -> { order(created_at: :desc) }

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
