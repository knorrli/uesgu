require "test_helper"

# Integrity of the venue registry (config/venues.yml, wrapped by Venue) — the
# code-controlled source of truth the ledger projection, the location taxonomy, and
# discovery read from. Like the ledger drift test, this reads the REAL registry (no
# fixtures): it pins the Venue API + per-venue invariants the drift test doesn't
# cover (place shape, name matching). Source/scraper reconciliation lives in the
# drift test (every consume venue is backed by a live scraper).
class VenueTest < ActiveSupport::TestCase
  def venues = Venue.all

  test "registry is populated and every venue has a domain, name and valid status" do
    assert_operator venues.size, :>=, 50
    venues.each do |v|
      assert v.domain.present?, "#{v}: missing domain"
      assert v.name.present?,   "#{v.domain}: missing name"
      assert_includes Venue::STATUSES, v.status, "#{v.domain}: bad status #{v.status.inspect}"
    end
  end

  test "domains are unique and canonical eTLD+1" do
    dupes = venues.map(&:domain).tally.select { |_, n| n > 1 }.keys
    assert_empty dupes, "duplicate venue domains: #{dupes.join(', ')}"
    venues.each do |v|
      assert_equal v.domain, Scrapers::Discovery.domain(v.domain),
                   "#{v.domain.inspect} is not a canonical eTLD+1"
    end
  end

  test "blocked venues carry a known reason; consume venues carry none" do
    venues.each do |v|
      if v.consume?
        assert_nil v.reason, "#{v.domain}: a consume venue must not carry a reason"
      else
        assert v.reason, "#{v.domain}: a #{v.status} venue needs a reason"
        assert_includes Scrapers::Discovery::Ledger::REASONS.keys, v.reason.to_s,
                        "#{v.domain}: unknown reason #{v.reason.inspect}"
      end
    end
  end

  test "placed consume venues have a full [venue, city, canton] tuple" do
    Venue.in_taxonomy.each do |v|
      assert_equal 3, v.place_tuple.size, "#{v.domain}: incomplete place #{v.place_tuple.inspect}"
    end
  end

  test "the Bewegungsmelder aggregator feed is consumed but placeless, so out of the taxonomy" do
    bm = Venue.find_by_domain("bewegungsmelder.ch")
    assert bm.consume?, "expected the aggregator feed to be consumed"
    refute bm.placed?, "the feed host itself has no place"
    refute_includes Venue.in_taxonomy, bm
  end

  test "matches? normalizes case and whitespace" do
    d = Venue.find_by_domain("dachstock.ch")
    assert d.matches?("Dachstock")
    assert d.matches?("  DACHSTOCK  ")
    refute d.matches?("Gaskessel")
  end

  # Café Kairo carries a precomposed accent; an aggregator feed might emit the
  # decomposed form. Build the decomposed variant FROM the name so it's provably the
  # same name in a different normalization form (refute_equal guards that).
  test "matches? folds unicode normalization forms (NFC vs NFD)" do
    k = Venue.find_by_domain("cafe-kairo.ch")
    decomposed = k.name.unicode_normalize(:nfd)
    refute_equal k.name, decomposed, "expected a byte-wise-different decomposed form to test"
    assert k.matches?(decomposed), "matches? must be insensitive to NFC vs NFD"
  end

  test "matching resolves an aggregator's raw <location> name to the approved venue" do
    assert_equal "dachstock.ch", Venue.matching("dachstock")&.domain
    assert_nil Venue.matching("Totally Unknown Venue")
  end
end
