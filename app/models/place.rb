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
  include LocationTagFold

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
  scope :canonicals, -> { where(canonical_id: nil) }
  scope :aliased, -> { where.not(canonical_id: nil) }

  def to_s = name

  def self.fingerprint_for(str) = Fingerprint.for(str)

  # Resolves through a merge: a name stored as an alias yields its canonical.
  def self.matching(name)
    place = find_by(fingerprint: fingerprint_for(name))
    place&.canonical || place
  end

  def self.names = pluck(:name).to_set

  # Every place the taxonomy has since absorbed, for the drift report. Takes the
  # registry read out of the loop, which the per-row predicate cannot.
  def self.shadowed
    registry = Location.taxonomy_venue_fingerprints
    all.to_a.select { |place| place.shadowed?(registry) }
  end

  def alias? = canonical_id.present?

  # A captured venue that graduated to a consume row with a place, so this row is
  # duplicate identity rather than a place of its own. Registry-first precedence makes
  # it inert rather than wrong, but the graduating PR should delete it — `bin/rails
  # places:drift` is what makes that mechanical. Merging is not the fix: it would file
  # the events under a captured venue instead of the one we source from.
  def shadowed?(registry = Location.taxonomy_venue_fingerprints) = registry.include?(fingerprint)

  # Fold this place into the one it is a name for ("AKUT Thun" -> "AKuT"). The
  # canonical's town and canton win where the two rows disagree: an event cannot be
  # nested under one venue in the WHERE tree and filed in another venue's locality.
  def merge_into!(other)
    # Merging into an alias means merging into what that alias names — resolving here
    # is what keeps `canonical_id` one hop deep, which is all Place.matching follows.
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

  # Split an alias back out. Only the LINK is undone: the taggings and saved filters
  # the merge moved stay moved, exactly as splitting a locality does. What this
  # restores is the future — a capture under this spelling mints its own row again.
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

  # A name we already source from must resolve to that venue, not mint a second
  # identity for it. `:taken` is literally true and comes translated from
  # rails-i18n, so this invariant costs no new copy in three locales.
  def not_a_taxonomy_venue
    return if name.blank? || !Location.taxonomy_venue_fingerprints.include?(self.class.fingerprint_for(name))

    errors.add(:name, :taken)
  end
end
