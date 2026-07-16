# An admin-set, self-expiring mute for one scraper, keyed by its slug (the
# demodulized class name underscored — the same identity ScrapeResult#scraper
# uses). A snoozed scraper is skipped by the nightly Scrapers::Sweep and, the
# point of the feature, does NOT count toward the cron's failure alert — so a
# flaky venue stops paging you.
#
# The self-expiry is what makes this safe to forget: when snoozed_until passes
# the scraper simply runs again on the next sweep. If it's still broken the alert
# returns (that's your reminder); if it healed it resumes silently. "Leave it
# alone" is therefore the correct default — there is no switch to forget to flip
# back on. This is deliberately runtime/operational state (a DB row), distinct
# from the durable venue decisions in config/venues.yml.
class ScraperSnooze < ApplicationRecord
  DEFAULT_DURATION = 2.weeks

  validates :scraper, presence: true, uniqueness: true
  validates :snoozed_until, presence: true

  # Still muted right now. Expired rows are harmless (they stop matching); the
  # sweep clears them via #prune_expired! so they don't accumulate.
  scope :active, -> { where(snoozed_until: Time.current..) }

  # {slug => snooze} for the scrapers muted right now — the sweep's skip set and
  # the admin page's "until <date>" lookup.
  def self.active_by_slug
    active.index_by(&:scraper)
  end

  # Mute (or re-mute) one scraper for `duration` from now. Upsert on the unique
  # slug so re-snoozing an already-snoozed scraper just extends its window.
  def self.snooze!(scraper, duration: DEFAULT_DURATION)
    find_or_initialize_by(scraper: scraper).update!(snoozed_until: Time.current + duration)
  end

  # Wake a scraper immediately (admin clicked "Wake now").
  def self.wake!(scraper)
    where(scraper: scraper).delete_all
  end

  def self.prune_expired!
    where(snoozed_until: ...Time.current).delete_all
  end
end
