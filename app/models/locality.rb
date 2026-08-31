class Locality < ApplicationRecord
  include LocationTagFold

  belongs_to :canonical, class_name: "Locality", optional: true
  has_many :aliases, class_name: "Locality", foreign_key: :canonical_id,
                     inverse_of: :canonical, dependent: :nullify

  validates :name, presence: true

  scope :canonicals, -> { where(canonical_id: nil) }
  scope :aliased, -> { where.not(canonical_id: nil) }
  scope :in_use, -> { where("events_count > 0") }
  scope :unsettled, -> { canonicals.where(canton: nil) }
  scope :by_name, -> { order(Arel.sql("lower(name)")) }
  scope :by_usage, -> { order(events_count: :desc).order(Arel.sql("lower(name)")) }

  REGISTRY, CAPTURED, TAGGED = 0, 1, 2

  class << self
    def resolve(typed)
      row = matching(typed)
      row&.canonical || row
    end

    def matching(typed)
      return if typed.blank?

      find_by(fingerprint: Fingerprint.for(typed))
    end

    def canonical_name(typed) = resolve(typed)&.name || typed

    def canton_for(typed) = resolve(typed)&.canton

    def cantons_by_name = canonicals.by_name.pluck(:name, :canton).to_h

    def ensure!(names)
      representative = Array(names).filter_map { |name| [Fingerprint.for(name), name.to_s.strip] if name.present? }
                                   .reject { |key, _| key.blank? }.reverse.to_h
      return if representative.empty?

      representative.except(*where(fingerprint: representative.keys).pluck(:fingerprint)).each_value do |name|
        create!(name: name)
      rescue ActiveRecord::RecordNotUnique
        next
      end
    end

    def reconcile!
      seen = collect_sources
      ensure!(seen.values.map { |source| source[:name] })

      where(fingerprint: seen.keys).find_each do |locality|
        source = seen[locality.fingerprint]
        locality.update!(name: source[:name], canton: settled_canton(source[:cantons]),
                         events_count: source[:count])
        locality.normalize_spellings! unless source[:spellings].subset?(Set[locality.name])
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

        source = record(seen, tag[:name], nil, TAGGED, tag[:count])
        source[:spellings] << tag[:name] if source
      end
      seen.each_value { |source| source[:name] = source[:candidates].min.last }
      seen
    end

    def record(seen, name, canton, priority, count = 0)
      key = Fingerprint.for(name)
      return if key.blank?

      source = seen[key] ||= { candidates: [], spellings: Set.new, cantons: Set.new, count: 0 }
      source[:candidates] << [priority, -count, name.to_s.strip]
      source[:cantons] << canton if canton.present?
      source[:count] += count
      source
    end

    def settled_canton(cantons)
      cantons.first if cantons.one?
    end
  end

  def alias? = canonical_id.present?

  def registry? = Venue.in_taxonomy.any? { |venue| Fingerprint.for(venue.locality) == fingerprint }

  def merge_into!(other)
    target = other.canonical || other
    raise ArgumentError, "a locality cannot be merged into itself" if target.id == id
    raise ArgumentError, "a registry locality cannot be merged away" if registry?

    transaction do
      update!(canonical_id: target.id)
      aliases.update_all(canonical_id: target.id)
      normalize_spellings!(target.name)
    end
    Locality.reconcile!
  end

  def normalize_spellings!(canonical_name = name)
    transaction do
      retag_events(add: [canonical_name])
      move_places(canonical_name)
      rewrite_saved_filters(canonical_name)
    end
  end

  def unmerge!
    update!(canonical_id: nil)
    Locality.reconcile!
  end

  private

  def move_places(canonical_name)
    Place.where.not(locality: canonical_name).find_each do |place|
      place.update!(locality: canonical_name) if Fingerprint.for(place.locality) == fingerprint
    end
  end
end
