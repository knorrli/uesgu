class ScrapeRun < ApplicationRecord
  has_many :scrape_results, dependent: :destroy
  has_many :created_events, class_name: "Event",
                            foreign_key: :created_in_scrape_run_id,
                            dependent: :nullify,
                            inverse_of: :created_in_scrape_run

  enum :status, { running: "running", finished: "finished" }, default: "running"

  scope :recent, -> { order(started_at: :desc) }
  STALE_AFTER = 20.minutes
  scope :in_progress, -> { running.where(started_at: STALE_AFTER.ago..) }

  KEEP = 60
  def self.prune!(keep: KEEP)
    keep_ids = recent.limit(keep).pluck(:id)
    where.not(id: keep_ids).delete_all if keep_ids.any?
  end

  def needs_attention?
    scrapers_failed.positive? || scrapers_empty.positive?
  end

  def previous
    self.class.finished.where(started_at: ...started_at).recent.first
  end

  def dropped_to_zero
    prev = previous or return []
    baseline = prev.scrape_results.ok.pluck(:scraper).to_set
    scrape_results.empty.pluck(:scraper).select { |slug| baseline.include?(slug) }
  end

  def duration
    return unless started_at && finished_at

    finished_at - started_at
  end
end
