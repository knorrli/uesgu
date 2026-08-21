# A captured place: where a user-captured event happens, when the venue registry
# (config/venues.yml via Venue) does not cover it. Deliberately the COMPLEMENT of
# the registry, never a mirror of it — a venue we source from gets no Place row,
# and Location resolves the registry first: two sources of "what is a venue" is the
# mistake the retired VenuePlace model made. The complement is drawn at
# Venue.in_taxonomy, not at the whole file — a venue we decided not to scrape can
# still host a captured show.
#
# Not an owner of events: a vocabulary with attributes, like Genre. Events carry
# [name, locality, canton] as flat location tags because that is what the WHERE
# filter matches on (Filter#ransack_query → locations_name_in), so there is no
# place_id, and counts come from the taggings (Location.usage).
class Place < ApplicationRecord
  # An alias for a spelling the fingerprint cannot collapse ("Quarterfest" →
  # "Quartierfest"), kept so a future capture of the bad spelling still resolves.
  # Nullify rather than cascade: losing a canonical must not delete the alias.
  belongs_to :canonical, class_name: "Place", optional: true
  has_many :aliases, class_name: "Place", foreign_key: :canonical_id,
                     inverse_of: :canonical, dependent: :nullify

  validates :name, :locality, :canton, presence: true
  validates :canton, inclusion: { in: Location::CANTON_CODES, allow_blank: true }
  validate :fingerprint_available
  validate :not_a_taxonomy_venue

  scope :by_name, -> { order(name: :asc) }

  def to_s = name

  def self.fingerprint_for(str) = Fingerprint.for(str)

  # Resolves through a merge: a name stored as an alias yields its canonical.
  def self.matching(name)
    place = find_by(fingerprint: fingerprint_for(name))
    place&.canonical || place
  end

  def self.names = pluck(:name).to_set

  # Places the taxonomy has since absorbed: a captured venue that graduated to a
  # consume row with a place. Registry-first precedence makes them inert rather
  # than wrong, but they are duplicate identity and the graduating PR should
  # delete them — `bin/rails places:drift` is what makes that mechanical.
  def self.shadowed
    registry = Location.taxonomy_venue_fingerprints
    all.to_a.select { |place| registry.include?(place.fingerprint) }
  end

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

  # A name we already source from must resolve to that venue, not mint a second
  # identity for it. `:taken` is literally true and comes translated from
  # rails-i18n, so this invariant costs no new copy in three locales.
  def not_a_taxonomy_venue
    return if name.blank? || !Location.taxonomy_venue_fingerprints.include?(self.class.fingerprint_for(name))

    errors.add(:name, :taken)
  end
end
