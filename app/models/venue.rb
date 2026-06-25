# A venue: the single, code-controlled record of what place we cover, what we've
# DECIDED about it, and the discovery keys it answers to. The data lives in
# config/venues.yml (one row per venue); this PORO wraps a row to give the computed
# API, and `Venue.all` is the registry the ledger projection, the location
# taxonomy, and discovery read from. See docs/venue-registry-design.md.
#
# Not an ActiveRecord model — a plain value object over YAML, like Location is a
# plain class over the scraper registry. (VenuePlace is the separate AR table for
# aggregator-resolved places.)
#
# IDENTITY + DECISION live in the YAML; SOURCING (which scraper / OLE feed / PETZI
# slug feeds a venue) is DERIVED from the live registry, not stored here — so there
# is no redundant wiring string to drift. See `venues:inventory`.
class Venue
  CONFIG_PATH = Rails.root.join("config/venues.yml")
  STATUSES = %w[consume defer reject].freeze

  # One declared, data-shaped source (see docs/venue-registry-design.md "End
  # state"). Bespoke/PETZI sourcing is derived from the live registry by domain and
  # isn't listed here; this is for sourcing that has no other home — today, an OLE
  # aggregator that resolves this venue per event (`via: ole, aggregator: <label>`).
  # `matches` lists the raw <location> names the aggregator emits for this venue
  # (defaults to the venue name).
  Source = Struct.new(:via, :aggregator, :matches, keyword_init: true) do
    def aggregator? = aggregator.present?
  end

  class << self
    # The registry: every venue, memoized. Cleared automatically on code reload in
    # dev (the class is redefined); edit the YAML → restart, like any config.
    def all
      @all ||= load_file.map { |row| new(row) }
    end

    def reload! = (@all = nil)

    def find_by_domain(domain) = all.find { |v| v.domain == domain }

    def consuming = all.select(&:consume?)

    # Placed, consumed venues — the ones that seed the location taxonomy. Excludes
    # blocked venues and placeless ones (e.g. the Bewegungsmelder aggregator feed).
    def in_taxonomy = consuming.select(&:placed?)

    # The approved venue an aggregator's per-event <location> name resolves to.
    def matching(raw_name) = all.find { |v| v.matches?(raw_name) }

    # Normalize a venue name for matching: NFC, lowercased, whitespace-collapsed.
    def normalize(str) = str.to_s.unicode_normalize(:nfc).downcase.gsub(/\s+/, " ").strip

    private

    def load_file
      data = YAML.safe_load_file(CONFIG_PATH, permitted_classes: [Date])
      Array(data.is_a?(Hash) ? data.fetch("venues") : data)
    end
  end

  attr_reader :domain, :name, :city, :canton, :status, :reason, :checked, :aliases, :sources

  def initialize(row)
    @domain  = row.fetch("domain")
    @name    = row["name"]
    place    = row["place"] || {}
    @city    = place["city"]
    @canton  = place["canton"]
    @status  = row["disposition"] || "consume"
    @reason  = row["reason"]
    @checked = row["checked"]
    @aliases = (row["aliases"] || {}).transform_values { |keys| Array(keys) }
    @sources = Array(row["sources"]).map do |s|
      Source.new(via: s["via"], aggregator: s["aggregator"], matches: Array(s["matches"]))
    end
  end

  def label = name
  def place_tuple = [name, city, canton].compact
  def placed? = city.present? && canton.present?
  def consume? = status == "consume"
  def blocked? = !consume?
  def disposition = status

  # OLE-aggregator sources that resolve this venue per event.
  def aggregator_sources = sources.select(&:aggregator?)

  # True when this venue is fed by an aggregator (e.g. Bewegungsmelder) rather than
  # a scraper covering its own domain — so the ledger drift check looks for it under
  # the aggregator, not its own host. See Scrapers::Ole#venue_domains.
  def sourced_via_aggregator? = aggregator_sources.any?

  # The aggregator labels feeding this venue (matched against a scraper's `label`).
  def aggregator_names = aggregator_sources.map(&:aggregator)

  # The raw <location> names this venue answers to when an aggregator resolves it
  # per event: its name, any explicit source `matches`, and any hinto aliases,
  # normalized. The closed-allowlist key.
  def match_keys
    ([name] + sources.flat_map(&:matches) + Array(aliases["hinto"]))
      .compact.map { |s| Venue.normalize(s) }.uniq
  end

  def matches?(raw) = match_keys.include?(Venue.normalize(raw))
end
