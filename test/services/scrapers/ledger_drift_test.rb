require "test_helper"

class Scrapers::LedgerDriftTest < Minitest::Test
  def setup
    @ledger = Scrapers::Discovery::Ledger.load
  end

  def registry_domains
    Scrapers::All.scrapers.values.flat_map(&:venue_domains).to_set
  end

  def test_every_consume_row_is_backed_by_a_scraper
    orphans = @ledger.consume_domains - registry_domains
    assert_empty orphans,
                 "Ledger marks these domains `consume` but no scraper covers them — " \
                 "remove the row or fix its `domain` (typo / renamed scraper): #{orphans.to_a.sort.join(', ')}"
  end

  def test_every_scraped_domain_has_a_consume_row
    missing = registry_domains - @ledger.consume_domains
    assert_empty missing,
                 "These domains are scraped but have no `consume` row in config/venues.yml — " \
                 "add a venue row (or, for a SaaS-hosted feed, override the scraper's `venue_domains`): #{missing.to_a.sort.join(', ')}"
  end

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

  def test_domains_are_canonical
    @ledger.entries.each do |e|
      assert_equal e.domain, Scrapers::Discovery.domain(e.domain),
                   "#{e.domain.inspect} is not a canonical eTLD+1 — normalize it (drop scheme/www./path)"
    end
  end

  def test_domains_are_unique
    dupes = @ledger.entries.map(&:domain).tally.select { |_, n| n > 1 }.keys
    assert_empty dupes, "Duplicate ledger rows for: #{dupes.join(', ')}"
  end

  def test_aliases_resolve_to_a_single_domain
    clashes = @ledger.alias_pairs
                     .group_by { |upstream, key, _domain| [upstream, key] }
                     .select { |_, pairs| pairs.map(&:last).uniq.size > 1 }
    assert_empty clashes,
                 "These upstream keys map to more than one domain: " \
                 "#{clashes.map { |(u, k), pairs| "#{u}:#{k} -> #{pairs.map(&:last).join('/')}" }.join('; ')}"
  end
end
