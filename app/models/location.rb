# Location tags (the `:locations` acts_as_taggable_on context on Event) are flat:
# a single tag list mixing venues, cities, and canton codes. There is no stored
# type. We DERIVE the type from the VENUE REGISTRY (config/venues.yml via Venue):
# the placed, consumed venues (Venue.in_taxonomy) are the source of truth for the
# venue/city/canton roles and for the WHERE-filter tree.
#
# (Until 2026-06-25 this was derived from the scrapers + the VenuePlace table, now
# repurposed as VenueLead; the
# registry unified both — a bespoke scraper and an aggregator-resolved venue are now
# the same kind of row, so the taxonomy reads one place. A venue's `name` must equal
# the location tag its events carry, which the ledger drift + registry keep true.)
class Location
  include ActiveModel::Model

  # The placed, consumed venues that seed the taxonomy. A consume venue with a
  # city + canton — whether fed by a bespoke scraper, PETZI, or an aggregator.
  # Placeless venues (e.g. the Bewegungsmelder aggregator feed itself) are excluded.
  def self.taxonomy_venues
    Venue.in_taxonomy
  end

  # Every venue name in the taxonomy.
  def self.venue_names
    taxonomy_venues.map(&:name).to_set
  end

  # Every canton code in the taxonomy.
  def self.canton_codes
    taxonomy_venues.map(&:canton).to_set
  end

  # :venue for a concrete venue, :canton for a canton code, :city otherwise. The
  # canton codes are the registry's; anything else that is not a venue is a city.
  def self.type_for(name)
    name = name.to_s
    return :venue if venue_names.include?(name)
    return :canton if canton_codes.include?(name)

    :city
  end

  def self.venue?(name)
    venue_names.include?(name.to_s)
  end

  # Every location tag actually in use, as { name:, count:, type: } rows for the
  # admin locations browser. Counts come from the taggings (a location has no table
  # of its own); the type is the same registry-derived classification as type_for.
  # Tags that no event carries don't appear — this is "what's live".
  def self.usage
    # Classify against the venue/canton sets computed ONCE (each is a small read),
    # not via type_for per tag — this runs on the hot WHERE-filter path.
    venues = venue_names
    cantons = canton_codes
    ActsAsTaggableOn::Tagging
      .where(context: "locations", taggable_type: Event.name)
      .joins(:tag)
      .group("tags.name")
      .count
      .map do |name, count|
        type = venues.include?(name) ? :venue : (cantons.include?(name) ? :canton : :city)
        { name: name, count: count, type: type }
      end
  end

  # Grouped tree for the favorites + WHERE filter UI:
  #   { "BE" => { "Bern" => ["Dachstock", "Gaskessel", ...] }, ... }
  # Built from each placed, consumed venue. A venue too thin to place (no city or
  # canton) is skipped — Venue.in_taxonomy already excludes those, so no nil keys.
  def self.hierarchy
    taxonomy_venues.each_with_object({}) do |venue, tree|
      add_to_tree(tree, venue.canton, venue.city, venue.name)
    end
  end

  # Nest venue under canton > city, skipping a tuple too thin to place.
  def self.add_to_tree(tree, canton, city, venue)
    return if canton.blank? || city.blank? || venue.blank?

    tree[canton] ||= {}
    (tree[canton][city] ||= []) << venue
  end
end
