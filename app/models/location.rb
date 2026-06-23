# Location tags (the `:locations` acts_as_taggable_on context on Event) are flat:
# a single tag list mixing venues, cities, and canton codes. There is no stored
# type. We DERIVE the type from the scrapers, which are the source of truth — each
# scraper represents one venue and declares its place as
# `[venue, *aliases, city, canton_code]` (see app/services/scrapers/*).
#
# All scrapers are force-loaded at boot (config/application.rb), so the lists below
# are always complete and stay in sync automatically when a scraper is added.
class Location
  include ActiveModel::Model

  # The single-venue scrapers — the ones that declare a real [venue, city, canton]
  # place. Multi-venue aggregators (e.g. Petzi) resolve the venue per event and
  # carry only a placeholder class-level location, so they'd pollute the taxonomy
  # (and crash the favorites hierarchy with a nil city). Their venues already
  # appear via the dedicated scrapers, so dropping them here loses nothing.
  def self.place_scrapers
    Scrapers::All.scrapers.values.reject(&:aggregator?)
  end

  # Places a multi-venue aggregator resolved per-event at scrape time (VenuePlace).
  # Single-venue scrapers declare their place in code, so they feed the lists
  # below directly; a per-event aggregator can't, and AATO flattens its tuples on
  # the event — so we fold these persisted tuples in too, giving the aggregator's
  # venues (e.g. Bewegungsmelder's Heitere Fahne) the same taxonomy treatment.
  def self.aggregator_places
    VenuePlace.all
  end

  # The venues our scrapers cover (each scraper's `self.location`) plus the venues
  # aggregators resolved at scrape time.
  def self.venue_names
    (place_scrapers.map(&:location) + aggregator_places.map(&:venue)).to_set
  end

  # The canton codes our scrapers cover (each scraper's last location element) plus
  # those carried by aggregator-resolved places.
  def self.canton_codes
    (place_scrapers.map { |scraper| scraper.locations.last } +
      aggregator_places.filter_map(&:canton)).to_set
  end

  # :venue for a concrete venue, :canton for a canton code, :city otherwise. The
  # canton code is the last element each scraper declares; anything else that is
  # not a venue is treated as a city.
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
  # admin locations browser. Counts come from the taggings (a location has no
  # table of its own); the type is the same scraper-derived classification as
  # type_for. Tags that no event carries don't appear — this is "what's live".
  def self.usage
    # Classify against the venue/canton sets computed ONCE (each is a small query),
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
  # Built from each single-venue scraper's locations array, then extended with the
  # places aggregators resolved at scrape time (VenuePlace) so their venues nest
  # under the right city/canton — the structure AATO's flat tags can't recover.
  def self.hierarchy
    tree = place_scrapers.each_with_object({}) do |scraper, acc|
      locations = scraper.locations
      add_to_tree(acc, locations.last, locations[-2], scraper.location)
    end
    aggregator_places.each { |p| add_to_tree(tree, p.canton, p.city, p.venue) }
    tree
  end

  # Nest venue under canton > city, skipping a tuple too thin to place.
  def self.add_to_tree(tree, canton, city, venue)
    return if canton.blank? || city.blank? || venue.blank?

    tree[canton] ||= {}
    (tree[canton][city] ||= []) << venue
  end
end
