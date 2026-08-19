# A captured place: where a user-captured event happens, when the venue registry
# (config/venues.yml via Venue) does not cover it. Deliberately the COMPLEMENT of
# the registry, never a mirror of it — a registry venue gets no Place row, and
# Location resolves the registry first. Two sources of "what is a venue" is what
# VenuePlace was, and why PR #29 retired it. See docs/user-event-capture-design.md.
#
# Not an owner of events: a vocabulary with attributes, like Genre. Events carry
# [name, locality, canton] as flat location tags because that is what the WHERE
# filter matches on (Filter#ransack_query → locations_name_in), so there is no
# place_id, and counts come from the taggings (Location.usage).
class Place < ApplicationRecord
  # A merged-away spelling the fingerprint can't collapse ("Quarterfest" →
  # "Quartierfest"), kept as a row so a future capture of the bad spelling still
  # resolves. Nullify rather than cascade: losing a canonical must not delete it.
  belongs_to :canonical, class_name: "Place", optional: true
  has_many :aliases, class_name: "Place", foreign_key: :canonical_id,
                     inverse_of: :canonical, dependent: :nullify

  validates :name, :locality, :canton, presence: true
  validates :canton, inclusion: { in: Location::CANTON_CODES, allow_blank: true }
  validate :not_a_registry_venue

  scope :by_name, -> { order(name: :asc) }

  def to_s = name

  # The normalized matching key. MUST reproduce the SQL `fingerprint` generated
  # column exactly (CreatePlaces) — locked by a round-trip test. Used before a row
  # exists, on the raw name an extraction returned.
  def self.fingerprint_for(str) = Fingerprint.for(str)

  # The place a raw extracted name resolves to, following a merge to its
  # canonical. nil when we've never seen the name.
  def self.matching(name)
    place = find_by(fingerprint: fingerprint_for(name))
    place&.canonical || place
  end

  # Every captured place name, for Location's venue classification.
  def self.names = pluck(:name).to_set

  # Places the registry has since absorbed: a captured venue that graduated to a
  # config/venues.yml row. Registry-first precedence makes them inert rather than
  # wrong, but they are duplicate identity and the graduating PR should delete
  # them — `bin/rails places:drift` is what makes that mechanical.
  def self.shadowed
    registry = Location.venue_registry_fingerprints
    all.to_a.select { |place| registry.include?(place.fingerprint) }
  end

  private

  # The complement rule, enforced rather than remembered: a name the registry
  # already covers must resolve to that venue, not mint a second identity for it.
  # Matched by fingerprint, so a variant spelling cannot slip past. `:taken` is
  # literally true (a registry venue holds the name) and comes translated from
  # rails-i18n, so this invariant costs no new copy in three locales.
  def not_a_registry_venue
    return if name.blank? || !Location.venue_registry_fingerprints.include?(self.class.fingerprint_for(name))

    errors.add(:name, :taken)
  end
end
