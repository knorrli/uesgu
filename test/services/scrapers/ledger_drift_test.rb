require "test_helper"

# Drift detection for the venue registry (config/venues.yml), via its ledger
# projection. The registry is the authoritative "have we decided on this source?"
# record; these rules keep it reconciled with the live scraper registry and
# internally well-formed, so it can never silently diverge from what we actually
# scrape. A failure here means the registry and the code disagree — the message
# says exactly how. See docs/venue-registry-design.md and docs/discovery-design.md.
#
# This is data hygiene, not behaviour: it reads the real registry + the real
# scraper registry, no fixtures, no DB.
class Scrapers::LedgerDriftTest < Minitest::Test
  def setup
    @ledger = Scrapers::Discovery::Ledger.load
  end

  # Every domain any registered scraper covers (single-venue: one; Petzi: 14;
  # a per-event aggregator: none). The unit of reconciliation — one scraper can
  # cover many domains, one domain can be covered by many scrapers (Dachstock via
  # bespoke + OLE + Petzi), so we compare domain SETS, not scraper classes.
  def registry_domains
    Scrapers::All.scrapers.values.flat_map(&:venue_domains).to_set
  end

  # Rule 1 — no orphan consume row: every `consume` entry is backed by a live
  # scraper. A failure means a ledger row is stale (its scraper was renamed/deleted)
  # or its `domain` is typo'd.
  def test_every_consume_row_is_backed_by_a_scraper
    orphans = @ledger.consume_domains - registry_domains
    assert_empty orphans,
                 "Ledger marks these domains `consume` but no scraper covers them — " \
                 "remove the row or fix its `domain` (typo / renamed scraper): #{orphans.to_a.sort.join(', ')}"
  end

  # Rule 2 — no unrecorded scraper: every domain a scraper covers has a `consume`
  # row. A failure means a scraper was added (or its venue_domains changed) without
  # recording the decision in the ledger. This is the rule that disciplines new
  # direct-venue scrapers.
  def test_every_scraped_domain_has_a_consume_row
    missing = registry_domains - @ledger.consume_domains
    assert_empty missing,
                 "These domains are scraped but have no `consume` row in config/venues.yml — " \
                 "add a venue row (or, for a SaaS-hosted feed, override the scraper's `venue_domains`): #{missing.to_a.sort.join(', ')}"
  end

  # Rule 3 — reason well-formedness: defer/reject carry a valid reason; consume
  # carries none; disposition is one of the three.
  def test_dispositions_and_reasons_are_well_formed
    @ledger.entries.each do |e|
      assert_includes Scrapers::Discovery::Ledger::DISPOSITIONS, e.disposition,
                      "#{e.domain}: unknown disposition #{e.disposition.inspect}"
      if e.consume?
        assert_nil e.reason, "#{e.domain}: a `consume` row must not carry a reason"
      else
        refute_nil e.reason, "#{e.domain}: a `#{e.disposition}` row needs a reason"
        assert @ledger.reason?(e.reason),
               "#{e.domain}: reason #{e.reason.inspect} is not defined in the `reasons:` block"
      end
    end
  end

  # Rule 4 — domains are normalized: each `domain` is already its own eTLD+1 (no
  # scheme/subdomain/path/uppercase). Catches a `www.` or a URL slipping into the key.
  def test_domains_are_canonical
    @ledger.entries.each do |e|
      assert_equal e.domain, Scrapers::Discovery.domain(e.domain),
                   "#{e.domain.inspect} is not a canonical eTLD+1 — normalize it (drop scheme/www./path)"
    end
  end

  # No duplicate rows: one row per domain.
  def test_domains_are_unique
    dupes = @ledger.entries.map(&:domain).tally.select { |_, n| n > 1 }.keys
    assert_empty dupes, "Duplicate ledger rows for: #{dupes.join(', ')}"
  end

  # Rule 5 — alias uniqueness: no single upstream raw key resolves to two domains.
  def test_aliases_resolve_to_a_single_domain
    clashes = @ledger.alias_pairs
                     .group_by { |upstream, key, _domain| [upstream, key] }
                     .select { |_, pairs| pairs.map(&:last).uniq.size > 1 }
    assert_empty clashes,
                 "These upstream keys map to more than one domain: " \
                 "#{clashes.map { |(u, k), pairs| "#{u}:#{k} -> #{pairs.map(&:last).join('/')}" }.join('; ')}"
  end

  # Parity guard: Petzi::VENUES (slug -> place) and Petzi::DOMAINS (slug -> domain)
  # must cover the same slugs, so neither can gain/lose a venue without the other.
  def test_petzi_venues_and_domains_stay_aligned
    assert_equal Scrapers::Petzi::VENUES.keys.sort, Scrapers::Petzi::DOMAINS.keys.sort,
                 "Petzi::VENUES and Petzi::DOMAINS have diverged — every slug needs both a place and a domain"
  end
end
