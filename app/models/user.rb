class User < ApplicationRecord
  FREQUENCIES = %w[weekly monthly].freeze

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

  def admin?
    admin
  end
end
