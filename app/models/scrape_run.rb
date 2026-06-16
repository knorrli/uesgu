# One nightly sweep across every scraper (see lib/tasks/scrapers.rake). Holds the
# per-scraper ScrapeResult rows and the events the sweep first created, so the
# admin oversight page can answer "did last night work?" at a glance.
class ScrapeRun < ApplicationRecord
  has_many :scrape_results, dependent: :destroy
  has_many :created_events, class_name: 'Event',
                            foreign_key: :created_in_scrape_run_id,
                            dependent: :nullify,
                            inverse_of: :created_in_scrape_run

  enum :status, { running: 'running', finished: 'finished' }, default: 'running'

  scope :recent, -> { order(started_at: :desc) }
  # A run that's still going. Time-bounded so a crashed run (left "running"
  # because the process died mid-sweep) stops blocking the manual trigger after
  # a full sweep would comfortably have finished.
  STALE_AFTER = 20.minutes
  scope :in_progress, -> { running.where(started_at: STALE_AFTER.ago..) }

  # Keep the most recent runs; drop the rest. delete_all leans on the DB foreign
  # keys (scrape_results cascade away, events' backlink nullifies) so it stays a
  # single statement regardless of history depth.
  KEEP = 60
  def self.prune!(keep: KEEP)
    keep_ids = recent.limit(keep).pluck(:id)
    where.not(id: keep_ids).delete_all if keep_ids.any?
  end

  # A scraper that failed (raised) or came back empty (ran but wrote nothing) is
  # the whole point of this feature — surface it.
  def needs_attention?
    scrapers_failed.positive? || scrapers_empty.positive?
  end

  # The most recent finished sweep before this one — the baseline for the
  # drop-to-zero check below.
  def previous
    self.class.finished.where(started_at: ...started_at).recent.first
  end

  # Scrapers that produced events in the previous sweep but came back empty in
  # this one: a silent drop-to-zero (HTTP 200, but the markup changed under us).
  # This is the regression worth alerting on — distinct from a venue that's
  # simply chronically empty (empty last run too), which we leave to the admin
  # page. Returns the offending scraper slugs.
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
