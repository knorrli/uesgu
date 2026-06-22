# One scraper's outcome within a ScrapeRun. The status is the headline signal;
# the counts (seen / created / updated / errored) explain it and seed any future
# "degraded" / trend detection.
class ScrapeResult < ApplicationRecord
  belongs_to :scrape_run

  enum :status, { ok: 'ok', empty: 'empty', failed: 'failed' }

  scope :attention, -> { where(status: %w[empty failed]) }

  def attention?
    empty? || failed?
  end

  def errored?
    errored_count.to_i.positive?
  end

  # Headline status for display. An "ok" run that nevertheless errored on some
  # rows is downgraded to a warning so it never reads as a clean success.
  def display_status
    ok? && errored? ? "errors" : status
  end
end
