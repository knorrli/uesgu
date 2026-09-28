class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :saved_filters, dependent: :destroy
  # Bookmarked individual events ("save this show"). class_name pinned because the
  # inflector singularizes "saves" → "safe".
  has_many :event_saves, class_name: "EventSave", dependent: :destroy
  has_many :saved_events, through: :event_saves, source: :event
  has_many :push_subscriptions, dependent: :destroy
  has_many :genre_exclusions, dependent: :delete_all
  has_many :captured_events, class_name: "Event", foreign_key: :captured_by_id,
                             dependent: :nullify, inverse_of: :captured_by

  has_many :sent_invitations, class_name: "Invitation", foreign_key: :created_by_id, dependent: :destroy, inverse_of: :created_by
  has_one :accepted_invitation, class_name: "Invitation", foreign_key: :redeemed_by_id, dependent: :nullify, inverse_of: :redeemed_by

  PERMISSIONS = %w[curate_events genres places capture invite].freeze

  INVITE_ALLOWANCE = 5

  PERMISSION_AREAS = { "curate_events" => "events", "genres" => "genres", "places" => "places",
                       "invite" => "invites" }.freeze

  normalizes :username, with: ->(u) { u.strip.downcase }
  normalizes :permissions, with: ->(list) { list.map(&:to_s) & PERMISSIONS }
  normalizes :email_address, with: ->(e) { e.strip.downcase.presence }

  validates :username, presence: true, uniqueness: true, length: { in: 2..30 },
                       format: { with: /\A[a-z0-9_.-]+\z/, message: "may only contain letters, numbers, and . _ -" }
  validates :email_address, uniqueness: true, allow_nil: true
  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }, allow_blank: true
  validates :reminder_time, numericality: { in: 0..1439 }
  validates :reminder_lead_days, numericality: { in: 0..7 }

  def can?(permission) = admin? || permissions.include?(permission.to_s)

  def invites_left
    INVITE_ALLOWANCE - sent_invitations.redeemed.count - sent_invitations.available.count
  end

  def may_invite_more? = admin? || invites_left.positive?

  def moderator? = admin? || PERMISSION_AREAS.keys.intersect?(permissions)

  def log_areas = admin? ? ActionLog::AREAS.values.uniq : PERMISSION_AREAS.values_at(*permissions).compact

  def regenerate_calendar_feed_token!
    update!(calendar_feed_token: self.class.generate_calendar_feed_token)
  end

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
