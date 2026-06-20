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
end
