class User < ApplicationRecord
  FREQUENCIES = %w[daily weekly biweekly monthly never].freeze

  # Digest cadence per frequency. "never" has no interval (notifications off).
  # "daily" is mainly for testing the delivery pipeline.
  FREQUENCY_INTERVALS = {
    "daily" => 1.day,
    "weekly" => 1.week,
    "biweekly" => 2.weeks,
    "monthly" => 1.month
  }.freeze

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :notifications, dependent: :destroy

  # Favorites: users follow locations and styles (genres stay internal).
  acts_as_taggable_on :locations, :styles

  normalizes :username, with: ->(u) { u.strip.downcase }
  normalizes :email_address, with: ->(e) { e.strip.downcase.presence }

  validates :username, presence: true, uniqueness: true, length: { in: 2..30 },
                       format: { with: /\A[a-z0-9_.-]+\z/, message: "may only contain letters, numbers, and . _ -" }
  validates :email_address, uniqueness: true, allow_nil: true
  validates :notification_frequency, inclusion: { in: FREQUENCIES }
  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }, allow_blank: true
  validates :events_view, inclusion: { in: %w[list calendar] }, allow_nil: true

  def admin?
    admin
  end

  # Digest interval for this user's frequency, or nil when notifications are off.
  def notification_interval
    FREQUENCY_INTERVALS[notification_frequency]
  end
end
