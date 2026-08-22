# Location tags (the `:locations` acts_as_taggable_on context on Event) are flat:
# a single tag list mixing venues, localities, and canton codes. There is no stored
# type. We DERIVE the type from two disjoint sources, registry first: venue names
# come from the VENUE REGISTRY (config/venues.yml via Venue) — the placed, consumed
# venues (Venue.in_taxonomy) — plus the captured PLACES (the Place table), which
# cover exactly what the registry does not. Canton codes are the closed list of 26
# (CANTON_CODES), independent of which cantons we happen to source from. Everything
# else is a locality.
#
# (Until 2026-06-25 this was derived from the scrapers + the VenuePlace table, now
# repurposed as VenueLead; the
# registry unified both — a bespoke scraper and an aggregator-resolved venue are now
# the same kind of row, so the taxonomy reads one place. A venue's `name` must equal
# the location tag its events carry, which the ledger drift + registry keep true.)
class Location
  include ActiveModel::Model

  # The placed, consumed venues that seed the taxonomy. A consume venue with a
  # locality + canton — whether fed by a bespoke scraper, PETZI, or an aggregator.
  # Placeless venues (e.g. the Bewegungsmelder aggregator feed itself) are excluded.
  def self.taxonomy_venues
    Venue.in_taxonomy
  end

  # Fingerprints of the taxonomy venue names — the key Place validates against, so
  # a captured place can never duplicate a venue we already source from. Narrower
  # than the registry on purpose: a deferred or rejected row is a decision not to
  # SCRAPE a venue, not a claim that nobody plays there, so a capture at one still
  # needs its own place.
  def self.taxonomy_venue_fingerprints
    taxonomy_venues.to_set { |venue| Fingerprint.for(venue.name) }
  end

  # The venue a typed name IS: the registry first, then the captured places, resolved
  # through a merge. Answers the Venue or the Place itself — both carry name, locality
  # and canton, which is the tuple an event is tagged with — or nil, which is the
  # normal answer for the one-off this funnel exists to catch.
  #
  # An EXACT fingerprint match and nothing looser. A near-match is what the suggestion
  # chips are for (see PlaceSuggester): "AKUT Thun" and "AKUT Bern" score alike and
  # can be two real venues, so taking one without a human would file a show at the
  # wrong address.
  def self.resolve_venue(typed)
    key = Fingerprint.for(typed)
    return if key.blank?

    taxonomy_venues.find { |venue| Fingerprint.for(venue.name) == key } || Place.matching(typed)
  end

  # The Place read lands on the per-event path (Event#venue). Inside a request the
  # query cache collapses it to one SELECT; a rake loop over events has no such
  # cache and should hoist this call out, the way usage below does.
  def self.venue_names
    taxonomy_venues.map(&:name).to_set | Place.names
  end

  # The 26 Swiss cantons, keyed by the code a location tag carries. This is a
  # CLOSED list and deliberately NOT registry-derived: which cantons we happen to
  # source venues from says nothing about which codes are cantons, and deriving it
  # made a tag for an uncovered canton (e.g. "VS") type as a locality. The display
  # names live in the `cantons:` map in config/locales/*.yml (TagsHelper#canton_name);
  # a test locks the two lists together so neither can drift.
  CANTON_CODES = %w[
    AG AI AR BE BL BS FR GE GL GR JU LU NE
    NW OW SG SH SO SZ TG TI UR VD VS ZG ZH
  ].to_set.freeze

  # Every canton code. A constant read — this sits on the hot WHERE-filter path.
  def self.canton_codes
    CANTON_CODES
  end

  # :venue for a concrete venue, :canton for a canton code, :locality otherwise.
  # A locality is any place name — city, town, village, hamlet or quarter.
  def self.type_for(name)
    name = name.to_s
    return :venue if venue_names.include?(name)
    return :canton if canton_codes.include?(name)

    :locality
  end

  def self.venue?(name)
    venue_names.include?(name.to_s)
  end

  # Every location tag actually in use, as { name:, count:, type: } rows for the
  # admin locations browser. Counts come from the taggings (a location has no table
  # of its own); the type is the same derived classification as type_for.
  # Tags that no event carries don't appear — this is "what's live".
  def self.usage
    # Classify against the venue/canton sets resolved ONCE (venues are a small read,
    # cantons a constant) — not via type_for per tag, this runs on the hot
    # WHERE-filter path.
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

  # Grouped tree for the favorites + WHERE filter UI:
  #   { "BE" => { "Bern" => ["Dachstock", "Gaskessel", ...] }, ... }
  # Built from each placed, consumed venue plus each captured place, so a captured
  # event is findable by browsing and not only by typing its exact name. A venue
  # too thin to place (no locality or canton) is skipped — Venue.in_taxonomy
  # already excludes those, so no nil keys; a Place cannot be thin (both NOT NULL).
  # One-offs need no expiry: location_filter_tree prunes every node to what events
  # currently carry, so a captured place leaves the tree when its show passes.
  def self.hierarchy
    tree = taxonomy_venues.each_with_object({}) do |venue, acc|
      add_to_tree(acc, venue.canton, venue.locality, venue.name)
    end
    Place.pluck(:canton, :locality, :name).each do |canton, locality, name|
      add_to_tree(tree, canton, locality, name)
    end
    tree
  end

  # Nest venue under canton > locality, skipping a tuple too thin to place.
  def self.add_to_tree(tree, canton, locality, venue)
    return if canton.blank? || locality.blank? || venue.blank?

    tree[canton] ||= {}
    (tree[canton][locality] ||= []) << venue
  end
end
