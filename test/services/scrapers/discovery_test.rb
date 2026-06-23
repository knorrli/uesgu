require "test_helper"

# Unit tests for the discovery diff logic (Scrapers::Discovery) — the pure
# functions the discovery:report rake feeds fetched upstream data into. Network +
# printing live in the rake; the resolution/clustering logic is tested here.
class Scrapers::DiscoveryTest < Minitest::Test
  D = Scrapers::Discovery

  # --- domain normalization ---

  def test_domain_normalizes_to_etld_plus_one
    assert_equal "dachstock.ch", D.domain("https://www.dachstock.ch/events")
    assert_equal "dachstock.ch", D.domain("api.dachstock.ch")
    assert_equal "sudpol.ch",    D.domain("https://cms.sudpol.ch/?rest_route=/x")
  end

  def test_domain_is_nil_for_a_bare_slug_or_blank
    assert_nil D.domain("dachstock") # a slug has no TLD — never false-resolves
    assert_nil D.domain("")
    assert_nil D.domain(nil)
  end

  # --- OLE registry diff ---

  def test_ole_unknown_domains_subtracts_ledger_and_ignores_hinto
    ledger = ledger_with("dachstock.ch", "birdseye.ch")
    sources = [
      "https://api.dachstock.ch/wp-json/ds/v1/hinto",   # known -> dropped
      "https://www.birdseye.ch/HintoEventlist.php",     # known -> dropped
      "https://www.futurina.ch/app/x/action/oleexport", # new
      "https://petrus.refbern.ch/app/refbern/x",        # new (church)
      "https://nydegg.refbern.ch/app/refbern/x",        # same eTLD+1 -> deduped
      "https://www.hinto.ch/de/app/hinto/action/oleexport/id/all" # aggregator -> ignored
    ]
    assert_equal %w[futurina.ch refbern.ch], D.ole_unknown_domains(sources, ledger)
  end

  # --- PETZI clustering ---

  def test_petzi_clusters_unknown_venues_and_drops_known_slugs
    urls = [
      petzi("sedel", "new-york-ska-jazz-ensemble"),          # known -> dropped
      petzi("chat-noir", "donne-ton-slam-au-chat"),          # unknown
      petzi("chat-noir", "standimpro-show"),                 # unknown, same venue
      petzi("chat-noir", "ema-catalyse-les-eleves"),         # unknown, same venue
      petzi("caves-du-manoir", "maquina-moja")               # unknown, singleton
    ]
    clusters = D.petzi_unknown_clusters(urls, Set["sedel"])

    chat = clusters.find { |c| c[:slug] == "chat-noir" }
    assert_equal 3, chat[:count]
    # the multi-token singleton venue keeps (at least) its leading tokens
    caves = clusters.find { |c| c[:slug].start_with?("caves-du") }
    assert_equal 1, caves[:count]
    refute(clusters.any? { |c| c[:slug] == "sedel" }, "known venue is not reported")
    # most-frequent first
    assert_equal "chat-noir", clusters.first[:slug]
  end

  def test_petzi_clusters_empty_when_all_known
    urls = [petzi("sedel", "a-show"), petzi("kiff", "another-show")]
    assert_empty D.petzi_unknown_clusters(urls, Set["sedel", "kiff"])
  end

  private

  def petzi(slug, title) = "https://www.petzi.ch/en/events/#{rand_id}-#{slug}-#{title}/"

  # deterministic-enough id; value is irrelevant to slug extraction
  def rand_id = (@seq = (@seq || 60_000) + 1)

  def ledger_with(*domains)
    rows = domains.map { |d| { "domain" => d, "disposition" => "consume" } }
    Scrapers::Discovery::Ledger.new("reasons" => {}, "venues" => rows)
  end
end
