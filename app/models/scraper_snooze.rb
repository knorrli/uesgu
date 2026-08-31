class ScraperSnooze < ApplicationRecord
  DEFAULT_DURATION = 2.weeks

  validates :scraper, presence: true, uniqueness: true
  validates :snoozed_until, presence: true

  scope :active, -> { where(snoozed_until: Time.current..) }

  def self.active_by_slug
    active.index_by(&:scraper)
  end

  def self.snooze!(scraper, duration: DEFAULT_DURATION)
    find_or_initialize_by(scraper: scraper).update!(snoozed_until: Time.current + duration)
  end

  def self.wake!(scraper)
    where(scraper: scraper).delete_all
  end

  def self.prune_expired!
    where(snoozed_until: ...Time.current).delete_all
  end
end
