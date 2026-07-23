require "test_helper"

# Locks the post-relaunch Südpol mechanics the offline golden can't cover: the
# list's `data-date` is only MIDNIGHT of the event day, and the real start time
# is combined in from the /api/event/<id> detail (unreachable in the golden
# harness, whose events therefore all sit at midnight). SYNTHETIC rows shaped
# like the live Contao markup — no real programme content.
class Scrapers::SuedpolTest < Minitest::Test
  def test_combines_list_date_with_detail_time
    row = row_for(detail: <<~HTML)
      <div class="event-item">
        <div class="event-item__time">19:00 Uhr</div>
      </div>
    HTML
    assert_equal "2026-01-06 19:00", scraper.event_start_time(row).strftime("%Y-%m-%d %H:%M")
  end

  def test_dot_separated_detail_time_parses_too
    row = row_for(detail: %(<div class="event-item__time">20.30 Uhr</div>))
    assert_equal "2026-01-06 20:30", scraper.event_start_time(row).strftime("%Y-%m-%d %H:%M")
  end

  def test_missing_detail_keeps_the_midnight_default
    row = row_for(detail: nil)
    assert_equal "2026-01-06 00:00", scraper.event_start_time(row).strftime("%Y-%m-%d %H:%M")
  end

  def test_event_url_is_the_alias_deep_link
    assert_equal "https://www.sudpol.ch/programm?event=zorp-night-2",
                 scraper.event_url(row_for(detail: nil))
  end

  def test_music_filter_keeps_any_music_category_and_drops_the_rest
    kept = ["Konzert", "Club", "Konzert, Sommer im Südpol", "Gastveranstaltung, Konzert"]
    dropped = ["Theater", "Tanz, zum Mitmachen", "Sommer im Südpol", ""]
    kept.each { |c| assert scraper.send(:music?, node_for(category: c)), "should keep #{c.inspect}" }
    dropped.each { |c| refute scraper.send(:music?, node_for(category: c)), "should drop #{c.inspect}" }
  end

  private

  def scraper
    @scraper ||= Scrapers::Suedpol.new
  end

  # 1767726000 = 2026-01-06 00:00 +01:00, a real midnight stamp from the site.
  def node_for(category: "Konzert", stamp: 1_767_726_000)
    html = <<~HTML
      <div class="event-list__item" data-event-id="99999"
           data-event-alias="zorp-night-2" data-date="#{stamp}">
        <div class="event-list__category">#{category}</div>
        <div class="event-list__title">Zorp Night</div>
      </div>
    HTML
    Nokogiri::HTML.fragment(html).at_css(".event-list__item")
  end

  def row_for(detail:)
    Scrapers::Suedpol::Row.new(
      node: node_for,
      detail: detail && Nokogiri::HTML.fragment(detail)
    )
  end
end
