namespace :discovery do
  # READ-ONLY triage report: which venues/feeds the upstream indices expose that
  # we don't already consume/defer/reject. Fetches each upstream, subtracts the
  # venue registry (config/venues.yml), and prints the unknowns for a human to
  # add. Never enables anything — the only write path is adding/editing a venue
  # row in a PR. See docs/venue-registry-design.md + docs/discovery-design.md.
  # Suitable for a periodic (weekly) cron.
  #
  #   bin/rails discovery:report
  desc "Report upstream venues/feeds we do not yet consume (read-only triage)"
  task report: :environment do
    ledger = Scrapers::Discovery::Ledger.load
    agent  = Scrapers::Agent.new # honest UA + robots.txt, like every scraper

    fetch = lambda do |label, url|
      doc = Nokogiri::XML(agent.get(url).body)
      doc.remove_namespaces!
      doc
    rescue StandardError => e
      warn "  ! could not fetch #{label} (#{url}): #{e.class}: #{e.message}"
      nil
    end

    # --- OLE registry: an XML list of per-venue feed URLs (hinto.ch/oleexport) ---
    ole_doc = fetch.call("OLE registry", "https://www.hinto.ch/oleexport")
    ole_sources = ole_doc ? ole_doc.css("sources source").map(&:text) : []
    ole_new = Scrapers::Discovery.ole_unknown_domains(ole_sources, ledger)

    # --- PETZI sitemap: event URLs whose venue slug we don't track ---
    petzi_doc  = fetch.call("PETZI sitemap", Scrapers::Petzi.url.to_s)
    petzi_urls = petzi_doc ? petzi_doc.css("loc").map(&:text).select { |u| u.include?("/events/") } : []
    known_slugs = ledger.alias_keys("petzi") | Scrapers::Petzi.venues.keys.to_set
    petzi_new = Scrapers::Discovery.petzi_unknown_clusters(petzi_urls, known_slugs)

    # --- Re-check: blocked venues whose revisitable reason may have gone stale ---
    recheck = ledger.stale_revisitable(Date.current)

    # --- Drift: ledger vs the live scraper registry (same check as the CI test) ---
    consume = ledger.consume_domains
    covered = Scrapers::All.scrapers.values.flat_map(&:venue_domains).to_set
    orphans = (consume - covered).to_a.sort
    missing = (covered - consume).to_a.sort

    puts "\nDISCOVERY REPORT — #{Date.current}"
    puts "=" * 60

    puts "\nOLE registry — #{ole_new.size} feed domain(s) not in the ledger:"
    ole_new.each { |d| puts "  #{d}" }
    puts "  (none)" if ole_new.empty?

    puts "\nPETZI — #{petzi_new.size} untracked venue slug(s) " \
         "(best-effort cluster; identify the venue, then add slug→domain):"
    petzi_new.each do |c|
      puts format("  %-28s %2d event(s)   e.g. %s", c[:slug], c[:count], c[:samples].first)
    end
    puts "  (none)" if petzi_new.empty?

    puts "\nRe-check — #{recheck.size} blocked venue(s) past the staleness window:"
    recheck.each { |e| puts "  #{e.domain}  (#{e.reason}, last checked #{e.checked})" }
    puts "  (none)" if recheck.empty?

    puts "\nDrift — ledger vs live scrapers:"
    if orphans.empty? && missing.empty?
      puts "  OK — ledger and registry reconcile"
    else
      orphans.each { |d| puts "  orphan consume row (no scraper): #{d}" }
      missing.each { |d| puts "  scraped but unrecorded: #{d}" }
    end
    puts
  end
end
