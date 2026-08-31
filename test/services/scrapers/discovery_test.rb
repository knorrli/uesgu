require "test_helper"

class Scrapers::DiscoveryTest < Minitest::Test
  D = Scrapers::Discovery

  def test_domain_normalizes_to_etld_plus_one
    assert_equal "dachstock.ch", D.domain("https://www.dachstock.ch/events")
    assert_equal "dachstock.ch", D.domain("api.dachstock.ch")
    assert_equal "sudpol.ch",    D.domain("https://cms.sudpol.ch/?rest_route=/x")
  end

  def test_domain_is_nil_for_a_bare_slug_or_blank
    assert_nil D.domain("dachstock")
    assert_nil D.domain("")
    assert_nil D.domain(nil)
  end

  def test_ole_unknown_domains_subtracts_ledger_and_ignores_hinto
    ledger = ledger_with("dachstock.ch", "birdseye.ch")
    sources = [
      "https://api.dachstock.ch/wp-json/ds/v1/hinto",
      "https://www.birdseye.ch/HintoEventlist.php",
      "https://www.futurina.ch/app/x/action/oleexport",
      "https://petrus.refbern.ch/app/refbern/x",
      "https://nydegg.refbern.ch/app/refbern/x",
      "https://www.hinto.ch/de/app/hinto/action/oleexport/id/all"
    ]
    assert_equal %w[futurina.ch refbern.ch], D.ole_unknown_domains(sources, ledger)
  end

  def test_petzi_clusters_unknown_venues_and_drops_known_slugs
    urls = [
      petzi("sedel", "new-york-ska-jazz-ensemble"),
      petzi("chat-noir", "donne-ton-slam-au-chat"),
      petzi("chat-noir", "standimpro-show"),
      petzi("chat-noir", "ema-catalyse-les-eleves"),
      petzi("caves-du-manoir", "maquina-moja")
    ]
    clusters = D.petzi_unknown_clusters(urls, Set["sedel"])

    chat = clusters.find { |c| c[:slug] == "chat-noir" }
    assert_equal 3, chat[:count]
    caves = clusters.find { |c| c[:slug].start_with?("caves-du") }
    assert_equal 1, caves[:count]
    refute(clusters.any? { |c| c[:slug] == "sedel" }, "known venue is not reported")
    assert_equal "chat-noir", clusters.first[:slug]
  end

  def test_petzi_clusters_empty_when_all_known
    urls = [petzi("sedel", "a-show"), petzi("kiff", "another-show")]
    assert_empty D.petzi_unknown_clusters(urls, Set["sedel", "kiff"])
  end

  private

  def petzi(slug, title) = "https://www.petzi.ch/en/events/#{rand_id}-#{slug}-#{title}/"

  def rand_id = (@seq = (@seq || 60_000) + 1)

  def ledger_with(*domains)
    rows = domains.map { |d| { "domain" => d, "disposition" => "consume" } }
    Scrapers::Discovery::Ledger.new("reasons" => {}, "venues" => rows)
  end
end
