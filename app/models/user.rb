class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :notifications, dependent: :destroy
  # User-defined notification funnels (the WHEN·WHICH·FILTER·CHANNEL rules).
  has_many :saved_filters, dependent: :destroy
  # Bookmarked individual events ("save this show"). class_name pinned because the
  # inflector singularizes "saves" → "safe".
  has_many :event_saves, class_name: "EventSave", dependent: :destroy
  has_many :saved_events, through: :event_saves, source: :event
  # Web Push opt-ins, one per browser/device. Gone with the account.
  has_many :push_subscriptions, dependent: :destroy

  # Invitations this user (an admin) minted. Gone with the account.
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :created_by_id, dependent: :destroy, inverse_of: :created_by
  # The single-use code this user redeemed to sign up, if any. Kept as an audit
  # record when the account is deleted (redeemed_at stays set), just unlinked.
  has_one :accepted_invitation, class_name: "Invitation", foreign_key: :redeemed_by_id, dependent: :nullify, inverse_of: :redeemed_by

  normalizes :username, with: ->(u) { u.strip.downcase }
  normalizes :email_address, with: ->(e) { e.strip.downcase.presence }

  validates :username, presence: true, uniqueness: true, length: { in: 2..30 },
                       format: { with: /\A[a-z0-9_.-]+\z/, message: "may only contain letters, numbers, and . _ -" }
  validates :email_address, uniqueness: true, allow_nil: true
  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }, allow_blank: true
  validates :events_view, inclusion: { in: %w[list calendar] }, allow_nil: true
  validates :saved_events_view, inclusion: { in: %w[list calendar] }, allow_nil: true
  validates :reminder_time, numericality: { in: 0..1439 }
  validates :reminder_lead_days, numericality: { in: 0..7 }

  def admin?
    admin
  end

  # Mint (or rotate) the bearer token behind the subscribable ICS feed. Rotating
  # silently invalidates any old subscription URL — the way to revoke one.
  def regenerate_calendar_feed_token!
    update!(calendar_feed_token: self.class.generate_calendar_feed_token)
  end

  # Drop the feed link entirely (the feed 404s afterwards).
  def clear_calendar_feed_token!
    update!(calendar_feed_token: nil)
  end

  def self.generate_calendar_feed_token
    loop do
      token = SecureRandom.urlsafe_base64(24)
      break token unless exists?(calendar_feed_token: token)
    end
  end
end
