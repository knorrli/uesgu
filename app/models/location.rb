class Location
  include ActiveModel::Model

  def self.taxonomy_venues
    Venue.in_taxonomy
  end

  def self.taxonomy_venue_fingerprints
    taxonomy_venues.to_set { |venue| Fingerprint.for(venue.name) }
  end

  def self.resolve_venue(typed)
    key = Fingerprint.for(typed)
    return if key.blank?

    taxonomy_venues.find { |venue| Fingerprint.for(venue.name) == key } || Place.matching(typed)
  end

  def self.venue_names
    taxonomy_venues.map(&:name).to_set | Place.names
  end

  CANTON_CODES = %w[
    AG AI AR BE BL BS FR GE GL GR JU LU NE
    NW OW SG SH SO SZ TG TI UR VD VS ZG ZH
  ].to_set.freeze

  def self.canton_codes
    CANTON_CODES
  end

  def self.type_for(name)
    name = name.to_s
    return :venue if venue_names.include?(name)
    return :canton if canton_codes.include?(name)

    :locality
  end

  def self.venue?(name)
    venue_names.include?(name.to_s)
  end

  def self.usage
    venues = venue_names
    cantons = canton_codes
    ActsAsTaggableOn::Tagging
      .where(context: "locations", taggable_type: Event.name)
      .joins(:tag)
      .group("tags.name")
      .count
      .map do |name, count|
        type = venues.include?(name) ? :venue : (cantons.include?(name) ? :canton : :locality)
        { name: name, count: count, type: type }
      end
  end

  def self.hierarchy
    tree = taxonomy_venues.each_with_object({}) do |venue, acc|
      add_to_tree(acc, venue.canton, venue.locality, venue.name)
    end
    Place.pluck(:canton, :locality, :name).each do |canton, locality, name|
      add_to_tree(tree, canton, locality, name)
    end
    tree
  end

  def self.add_to_tree(tree, canton, locality, venue)
    return if canton.blank? || locality.blank? || venue.blank?

    tree[canton] ||= {}
    (tree[canton][locality] ||= []) << venue
  end
end
