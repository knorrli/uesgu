namespace :venues do
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

  def place_of(venue)
    venue.placed? ? "#{venue.locality}, #{venue.canton}" : "—"
  end

  def sourcing_of(venue)
    return venue.reason.to_s if venue.blocked?

    labels = sources_for(venue.domain)
    labels += venue.aggregator_names.map { |name| "ole(#{name}, via aggregator)" }
    labels.empty? ? "(no source)" : labels.join("  ")
  end

  DIRECT_TRANSPORT = { "Bar59" => "api", "Dynamo" => "api" }.freeze

  def sources_for(domain)
    out = []
    Scrapers::All.scrapers.each do |name, klass|
      next if klass.aggregator? || name.start_with?("Ole")
      next unless klass.venue_domains.include?(domain)

      out << "direct(#{name}·#{DIRECT_TRANSPORT.fetch(name, 'html')})"
    end
    venue = Venue.find_by_domain(domain)
    venue&.ole_feeds&.each do |feed|
      out << "ole(#{Scrapers::Ole.feed_key(venue)}#{feed.aggregator_feed? ? ', aggregator' : ''})"
    end
    if (slug = Scrapers::Petzi.domains.key(domain))
      out << "petzi(#{slug})"
    end
    out
  end
end
