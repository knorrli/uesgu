# The middle tier of the WHERE tree — the town an event happens in — as rows rather
# than as the bare string it used to be in three places at once (places.locality,
# the venue registry's `place:` block, and a flat location tag on every event).
#
# Modelled on Genre, which solves the same problem for an equally open vocabulary: a
# stored `fingerprint` generated column folds spelling variants, `ensure!` mints a row
# for a name nobody has seen, `reconcile!` keeps the counts honest, and `canonical_id`
# links a name to the one it is an alias of. Events keep carrying raw string tags —
# there is no foreign key here, exactly as an event carries a genre's name and not
# its id.
#
# What is NOT like Genre: merging rewrites. A genre alias resolves at query time
# because one method (Genre.filter_names_for) is the only thing that has to know.
# Location.hierarchy, Location.usage, the filter-tree pruning and Filter#location_list
# all group on the literal tag string, so an alias nothing repoints would leave Biel
# and Bienne as two nodes of the tree holding half the events each — the thing the
# merge is asked to fix. See #merge_into!.
class Locality < ApplicationRecord
  belongs_to :canonical, class_name: "Locality", optional: true
  has_many :aliases, class_name: "Locality", foreign_key: :canonical_id,
                     inverse_of: :canonical, dependent: :nullify

  validates :name, presence: true

  scope :canonicals, -> { where(canonical_id: nil) }
  scope :aliased, -> { where.not(canonical_id: nil) }
  scope :in_use, -> { where("events_count > 0") }
  # No canton and no alias: either a town the registry has never placed, or one whose
  # sources disagree. Both are the admin's queue — a merge settles the second.
  scope :unsettled, -> { canonicals.where(canton: nil) }
  scope :by_name, -> { order(Arel.sql("lower(name)")) }
  scope :by_usage, -> { order(events_count: :desc).order(Arel.sql("lower(name)")) }

  # Registry first, so its PR-reviewed spelling is the one a row is minted under.
  REGISTRY, CAPTURED, TAGGED = 0, 1, 2

  class << self
    # The row a typed name is, with an alias resolved to the locality it names.
    def resolve(typed)
      row = matching(typed)
      row&.canonical || row
    end

    # Identity modulo case, accents and punctuation is not a near-match: "bern" and
    # "Bern" ARE the same name. The FINGERPRINT, not a similarity measure — no string
    # measure reaches Freiburg -> Fribourg (0.29 of their trigrams) or Genf -> Genève
    # (0.33), and there is no threshold that admits those and excludes unrelated
    # towns. That class is what an admin merge is for.
    def matching(typed)
      return if typed.blank?

      find_by(fingerprint: Fingerprint.for(typed))
    end

    # The spelling an event should be filed under. Falls through to what was typed:
    # a town nobody carries yet is a perfectly good answer — a hamlet is exactly what
    # the capture funnel exists to catch — and reconcile! mints its row.
    def canonical_name(typed) = resolve(typed)&.name || typed

    def canton_for(typed) = resolve(typed)&.canton

    # Name => canton for the capture card's locality list. Aliases are left out: two
    # options for one town is what merging exists to remove.
    def cantons_by_name = canonicals.by_name.pluck(:name, :canton).to_h

    # Mint rows for names not seen before, so a capture's fresh spelling is curatable
    # the moment it is published rather than after the next sweep. Mirrors
    # Genre.ensure!.
    def ensure!(names)
      # First spelling wins, so a caller that passes its sources in priority order
      # (see reconcile!) gets the row minted under the one it meant.
      representative = Array(names).filter_map { |name| [Fingerprint.for(name), name.to_s.strip] if name.present? }
                                   .reject { |key, _| key.blank? }.reverse.to_h
      return if representative.empty?

      representative.except(*where(fingerprint: representative.keys).pluck(:fingerprint)).each_value do |name|
        create!(name: name)
      rescue ActiveRecord::RecordNotUnique
        next # a concurrent insert already claimed the fingerprint
      end
    end

    # Re-derive the table from the three places a locality name actually lives, mint
    # anything new, and refresh the cached counts. Idempotent; runs after a sweep like
    # Genre.reconcile!, because a scraper minting a venue in a new town is the other
    # way a locality enters.
    def reconcile!
      seen = collect_sources
      ensure!(seen.values.map { |source| source[:name] })

      where(fingerprint: seen.keys).find_each do |locality|
        source = seen[locality.fingerprint]
        locality.update!(name: source[:name], canton: settled_canton(source[:cantons]),
                         events_count: source[:count])
      end
      where.not(fingerprint: seen.keys).update_all(events_count: 0)
    end

    private

    def collect_sources
      seen = {}
      Venue.in_taxonomy.each { |venue| record(seen, venue.locality, venue.canton, REGISTRY) }
      Place.distinct.pluck(:locality, :canton).each { |name, canton| record(seen, name, canton, CAPTURED) }
      Location.usage.each do |tag|
        next unless tag[:type] == :locality

        source = record(seen, tag[:name], nil, TAGGED)
        source[:count] += tag[:count] if source
      end
      seen
    end

    def record(seen, name, canton, priority)
      key = Fingerprint.for(name)
      return if key.blank?

      source = seen[key] ||= { name: nil, priority: nil, cantons: Set.new, count: 0 }
      if source[:priority].nil? || priority < source[:priority]
        source[:name] = name.to_s.strip
        source[:priority] = priority
      end
      source[:cantons] << canton if canton.present?
      source
    end

    # nil rather than a guess where the sources disagree: Buchs is a locality in SG,
    # AG, ZH and LU alike, and answering with whichever row loaded first is the
    # wrong-canton bug this abstention exists to prevent.
    def settled_canton(cantons)
      cantons.first if cantons.one?
    end
  end

  def alias? = canonical_id.present?

  # A town the venue registry names. Scrapers re-tag their events from
  # config/venues.yml every night, so this spelling is re-minted whatever the table
  # says — it is the one thing here that cannot be merged away.
  def registry? = Venue.in_taxonomy.any? { |venue| Fingerprint.for(venue.locality) == fingerprint }

  # Fold this locality into the one it is a name for ("Bienne" -> "Biel"). This
  # REWRITES, and deliberately: every read path groups on the literal tag string, so a
  # link nothing repoints leaves the town split across two nodes of the WHERE tree.
  # Every event carrying a name that folds onto this one is retagged and every
  # captured place under it is moved, while `canonical_id` keeps a capture arriving
  # under this spelling resolving to the canonical from here on — which is what makes
  # the merge survive the nightly re-derivation instead of being undone by it.
  def merge_into!(other)
    # Merging into an alias means merging into what that alias names — resolving here
    # is what keeps `canonical_id` one hop deep, which is all Locality.resolve follows.
    target = other.canonical || other
    raise ArgumentError, "a locality cannot be merged into itself" if target.id == id
    raise ArgumentError, "a registry locality cannot be merged away" if registry?

    transaction do
      update!(canonical_id: target.id)
      aliases.update_all(canonical_id: target.id)
      retag_events(target.name)
      move_places(target.name)
    end
    Locality.reconcile!
  end

  # Split an alias back out. Only the LINK is undone: the taggings and places the
  # merge moved stay moved, the same way restoring a blocked genre does not bring its
  # stripped taggings back. What this restores is the future — a capture under this
  # spelling files here again.
  def unmerge!
    update!(canonical_id: nil)
    Locality.reconcile!
  end

  private

  # Every location tag that folds onto this locality, not just its own spelling: a
  # tag minted before entry-time normalisation existed ("bern") shares this row and
  # has to travel with it.
  def variant_tag_names
    ActsAsTaggableOn::Tag.joins(:taggings)
                         .where(taggings: { context: "locations", taggable_type: Event.name })
                         .distinct.pluck(:name)
                         .select { |tag| Fingerprint.for(tag) == fingerprint }
  end

  # Snapshot the ids first: removing the tag shrinks the tagged_with set find_each
  # would page over, which would skip events and leave them on the old name.
  def retag_events(canonical_name)
    variant_tag_names.each do |variant|
      next if variant == canonical_name

      Event.where(id: Event.tagged_with(variant, on: :locations).pluck(:id)).find_each do |event|
        event.location_list.remove(variant)
        event.location_list.add(canonical_name)
        event.save!
      end
    end
  end

  # places.locality carries no fingerprint column of its own, so the fold happens in
  # Ruby. The table holds captured places only and stays small.
  def move_places(canonical_name)
    Place.where.not(locality: canonical_name).find_each do |place|
      place.update!(locality: canonical_name) if Fingerprint.for(place.locality) == fingerprint
    end
  end
end
