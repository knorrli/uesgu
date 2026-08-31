class Place < ApplicationRecord
  include LocationTagFold

  belongs_to :canonical, class_name: "Place", optional: true
  has_many :aliases, class_name: "Place", foreign_key: :canonical_id,
                     inverse_of: :canonical, dependent: :nullify

  validates :name, :locality, :canton, presence: true
  validates :canton, inclusion: { in: Location::CANTON_CODES, allow_blank: true }
  validate :fingerprint_available
  validate :not_a_taxonomy_venue

  scope :by_name, -> { order(name: :asc) }
  scope :canonicals, -> { where(canonical_id: nil) }
  scope :aliased, -> { where.not(canonical_id: nil) }

  def to_s = name

  def self.fingerprint_for(str) = Fingerprint.for(str)

  def self.matching(name)
    place = find_by(fingerprint: fingerprint_for(name))
    place&.canonical || place
  end

  def self.names = pluck(:name).to_set

  def self.shadowed
    registry = Location.taxonomy_venue_fingerprints
    all.to_a.select { |place| place.shadowed?(registry) }
  end

  def alias? = canonical_id.present?

  def shadowed?(registry = Location.taxonomy_venue_fingerprints) = registry.include?(fingerprint)

  def merge_into!(other)
    target = other.canonical || other
    raise ArgumentError, "a place cannot be merged into itself" if target.id == id
    raise ArgumentError, "a place the registry covers cannot be merged away" if shadowed?

    transaction do
      update!(canonical_id: target.id)
      aliases.update_all(canonical_id: target.id)
      retag_events(add: [target.name, target.locality, target.canton].compact_blank,
                   strip: [locality, canton])
      rewrite_saved_filters(target.name)
    end
  end

  def rename!(new_name)
    self.name = new_name.to_s.strip
    unless valid?
      restore_attributes
      return false
    end

    transaction do
      retag_events(add: [name, locality, canton].compact_blank)
      rewrite_saved_filters(name)
      save!
    end
    true
  end

  def unmerge! = update!(canonical_id: nil)

  private

  # The unique index on the generated column is the real guard, but it surfaces as
  # a RecordNotUnique — a 500 on a capture screen whose honest answer is "you
  # already have this place". The column is null until the row is written, so the
  # duplicate has to be found by the Ruby fingerprint. Check-then-create is racy by
  # construction; the index stays the backstop.
  def fingerprint_available
    return if name.blank?

    duplicates = self.class.where(fingerprint: self.class.fingerprint_for(name))
    duplicates = duplicates.where.not(id: id) if persisted?
    errors.add(:name, :taken) if duplicates.exists?
  end

  def not_a_taxonomy_venue
    return if name.blank? || !Location.taxonomy_venue_fingerprints.include?(self.class.fingerprint_for(name))

    errors.add(:name, :taken)
  end
end
