class Event < ApplicationRecord
  acts_as_taggable_on :locations, :genres

  belongs_to :created_in_scrape_run, class_name: "ScrapeRun", optional: true,
                                     inverse_of: :created_events

  # Users who bookmarked this event ("save this show"). class_name pinned because
  # the inflector singularizes "saves" → "safe".
  has_many :event_saves, class_name: "EventSave", dependent: :destroy

  belongs_to :discarded_by_rule, class_name: "DiscardRule", optional: true,
                                 inverse_of: :discarded_events

  belongs_to :canonical_event, class_name: "Event", optional: true,
                               inverse_of: :duplicate_events
  has_many :duplicate_events, class_name: "Event", foreign_key: :canonical_event_id,
                              dependent: :nullify, inverse_of: :canonical_event

  validates :title, :start_date, presence: true
  # A user-captured event has no source page. NULL only, never "": the unique index
  # doesn't compare NULLs but does compare empty strings, so a second url-less event
  # would collide.
  validates :url, presence: true, allow_nil: true

  scope :visible, -> { kept.where(hidden: false, discarded_by_rule_id: nil, canonical_event_id: nil) }
  scope :duplicates, -> { where.not(canonical_event_id: nil) }
  scope :canonical, -> { where(canonical_event_id: nil) }
  scope :discarded, -> { kept.where.not(discarded_by_rule_id: nil) }
  scope :cancelled, -> { where.not(cancelled_at: nil) }
  scope :rescheduled, -> { where.not(rescheduled_at: nil) }

  scope :kept, -> { where(dismissed_at: nil) }
  scope :dismissed, -> { where.not(dismissed_at: nil) }

  def cancelled?
    cancelled_at.present?
  end

  def rescheduled?
    rescheduled_at.present?
  end

  def captured?
    data_source == EventCapture::Creator::DATA_SOURCE
  end

  def dismissed?
    dismissed_at.present?
  end

  def discarded?
    discarded_by_rule_id.present?
  end

  def dismiss!
    update!(dismissed_at: Time.current) unless dismissed?
  end

  def undismiss!
    update!(dismissed_at: nil) if dismissed?
  end

  def merge_into!(canonical)
    raise ArgumentError, "cannot merge an event into itself" if canonical.id == id

    update!(canonical_event_id: canonical.id)
    lock_field!("canonical_event")
  end

  def mark_standalone!
    update!(canonical_event_id: nil)
    lock_field!("canonical_event")
  end

  OVERRIDABLE_FIELDS = %w[title description start_date start_time].freeze

  OVERRIDABLE_TAG_FIELDS = %w[genres].freeze

  OVERRIDABLE_LINK_FIELDS = %w[canonical_event].freeze

  LOCKABLE_FIELDS = (OVERRIDABLE_FIELDS + OVERRIDABLE_TAG_FIELDS + OVERRIDABLE_LINK_FIELDS).freeze

  def overridden?(field)
    overridden_fields.include?(field.to_s)
  end

  def lock_field!(field)
    field = field.to_s
    return unless LOCKABLE_FIELDS.include?(field) && !overridden?(field)

    update!(overridden_fields: overridden_fields + [field])
  end

  def release_field!(field)
    field = field.to_s
    return unless overridden?(field)

    update!(overridden_fields: overridden_fields - [field])
  end

  def self.ransackable_attributes(auth_object = nil)
    ["title", "description", "start_date"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["taggings", "locations", "genres"]
  end

  def venue
    locations.detect { |location| Location.venue?(location.name) }
  end

  def to_s
    [
      start_date.strftime("%y-%m-%d"),
      title.truncate(40),
      description&.truncate(20),
      locations.map(&:name).join(", ")
    ].compact_blank.join(" || ")
  end

  def genre_list=(value)
    super
    genre_list.replace(Genre.canonicalize_names(genre_list))
    genre_list.reject!(&:blank?)
    blocked = Genre.blocked_fingerprints
    genre_list.reject! { |name| blocked.include?(Genre.fingerprint_for(name)) } if blocked.any?
  end

  def recompute_visibility!
    Genre.ensure!(genre_list)
    self.hidden = hidden_by_genre?
    save!
  end

  def hidden_by_genre?
    fingerprints = genre_list.map { |name| Genre.fingerprint_for(name) }
    return false if fingerprints.empty?

    hidden = Genre.hidden.where(fingerprint: fingerprints).pluck(:fingerprint).to_set
    fingerprints.all? { |fingerprint| hidden.include?(fingerprint) }
  end
end
