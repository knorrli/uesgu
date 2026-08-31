class Venue
  CONFIG_PATH = Rails.root.join("config/venues.yml")
  STATUSES = %w[consume defer reject].freeze

  Source = Struct.new(:via, :aggregator, :matches, :feed_url, :link_via, :gate, :enabled,
                      keyword_init: true) do
    def feed? = feed_url.present?

    def aggregator_feed? = aggregator == true

    def via_aggregator = (aggregator if aggregator.is_a?(String))

    def enabled? = enabled != false
  end

  class << self
    def all
      @all ||= load_file.map { |row| new(row) }
    end

    def reload! = (@all = nil)

    def find_by_domain(domain) = all.find { |v| v.domain == domain }

    def consuming = all.select(&:consume?)

    def in_taxonomy = consuming.select(&:placed?)

    def matching(raw_name) = all.find { |v| v.matches?(raw_name) }

    def normalize(str) = str.to_s.unicode_normalize(:nfc).downcase.gsub(/\s+/, " ").strip

    private

    def load_file
      data = YAML.safe_load_file(CONFIG_PATH, permitted_classes: [Date])
      Array(data.is_a?(Hash) ? data.fetch("venues") : data)
    end
  end

  attr_reader :domain, :name, :locality, :canton, :status, :reason, :checked, :aliases, :sources

  def initialize(row)
    @domain  = row.fetch("domain")
    @name    = row["name"]
    place    = row["place"] || {}
    @locality = place["locality"]
    @canton  = place["canton"]
    @status  = row["disposition"] || "consume"
    @reason  = row["reason"]
    @checked = row["checked"]
    @aliases = (row["aliases"] || {}).transform_values { |keys| Array(keys) }
    @sources = Array(row["sources"]).map do |s|
      Source.new(via: s["via"], aggregator: s["aggregator"], matches: Array(s["matches"]),
                 feed_url: s["feed_url"], link_via: s["link_via"], gate: s["gate"], enabled: s["enabled"])
    end
  end

  def label = name
  def place_tuple = [name, locality, canton].compact
  def placed? = locality.present? && canton.present?
  def consume? = status == "consume"
  def blocked? = !consume?
  def disposition = status

  def ole_feeds = sources.select { |s| s.via.to_s == "ole" && s.feed? && s.enabled? }

  def sourced_via_aggregator? = aggregator_names.any?

  def aggregator_names = sources.filter_map(&:via_aggregator)

  def match_keys
    ([name] + sources.flat_map(&:matches) + Array(aliases["hinto"]))
      .compact.map { |s| Venue.normalize(s) }.uniq
  end

  def matches?(raw) = match_keys.include?(Venue.normalize(raw))
end
