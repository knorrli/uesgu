class ScrapeResult < ApplicationRecord
  belongs_to :scrape_run

  enum :status, { ok: "ok", empty: "empty", failed: "failed", snoozed: "snoozed" }

  scope :attention, -> { where(status: %w[empty failed]) }

  def attention?
    empty? || failed?
  end

  def errored?
    errored_count.to_i.positive?
  end

  def display_status
    ok? && errored? ? "errors" : status
  end
end
