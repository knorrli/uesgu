require "uri"

namespace :venues do
  # READ-ONLY inventory of the venue registry (config/venues.yml): every venue we
  # know, grouped by decision, showing where it is and HOW it's sourced. Identity +
  # decision come from the registry; SOURCING is DERIVED live from the scraper /
  # OLE / PETZI registries, so it can't drift from what actually runs. Writes
  # nothing. See docs/venue-registry-design.md.
  #
  #   bin/rails venues:inventory
  desc "Inventory the venue registry: who we cover and how it's sourced (read-only)"
  task inventory: :environment do
    venues = Venue.all.sort_by { |v| v.name.to_s.downcase }
    by_status = venues.group_by(&:status)
    counts = Venue::STATUSES.map { |s| "#{by_status.fetch(s, []).size} #{s}" }.join(" · ")

    puts "\nVENUE INVENTORY — #{venues.size} venues (#{counts})"
    puts "=" * 72

    Venue::STATUSES.each do |status|
      group = by_status.fetch(status, [])
      next if group.empty?

      puts "\n#{status.upcase} (#{group.size})"
      group.each { |v| puts format("  %-22s %-22s %-12s %s", v.name, v.domain, place_of(v), sourcing_of(v)) }
    end
    puts
  end

  # "Bern, BE" / "—" when the venue carries no place (blocked or an aggregator feed).
  def place_of(venue)
    venue.placed? ? "#{venue.city}, #{venue.canton}" : "—"
  end

  # How a venue is actually fed, derived from the live registry. Blocked venues show
  # their reason (they have no live source).
  def sourcing_of(venue)
    return venue.reason.to_s if venue.blocked?

    # Derived sourcing (bespoke / single-venue OLE / PETZI, by domain) plus any
    # aggregator source the venue declares (resolved per event, so not domain-derivable).
    labels = sources_for(venue.domain)
    labels += venue.aggregator_sources.map { |s| "ole(#{s.aggregator}, via aggregator)" }
    labels.empty? ? "(no source)" : labels.join("  ")
  end

  # Best-effort transport hint for the bespoke scrapers that aren't plain HTML — a
  # display aid only, not load-bearing config (default: html).
  DIRECT_TRANSPORT = { "Bar59" => "api", "Dynamo" => "api" }.freeze

  def sources_for(domain)
    out = []
    Scrapers::All.scrapers.each do |name, klass|
      next if klass.aggregator? || name.start_with?("Ole")
      next unless klass.venue_domains.include?(domain)

      out << "direct(#{name}·#{DIRECT_TRANSPORT.fetch(name, 'html')})"
    end
    Scrapers::Ole::SOURCES.each do |s|
      next unless Scrapers::Discovery.domain(URI.parse(s[:feed_url]).host) == domain

      out << "ole(#{s[:key]}#{s[:aggregator] ? ', aggregator' : ''})"
    end
    if (slug = Scrapers::Petzi::DOMAINS.key(domain))
      out << "petzi(#{slug})"
    end
    out
  end
end
