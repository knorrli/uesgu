require 'test_helper'

# Locks the per-scraper event_genre_prose selectors for the five venues that
# opt into ingest-time prose genre-mining (B1). It asserts each hook pulls the
# right blurb out of the committed fixture by checking for the venue's OWN words —
# not taxonomy content — so it's churn-proof and stays DB-free (the matching of
# those words against the genre vocabulary is covered by GenreQueryTest, and the
# build_event composition by GenreMintingTest).
class Scrapers::DescriptionMiningTest < Minitest::Test
  FIXTURE_ROOT = File.expand_path('../../fixtures/scrapers', __dir__)

  def fixture(slug, name)
    File.read(File.join(FIXTURE_ROOT, slug, name))
  end

  def html(slug, name = 'list.html')
    Nokogiri::HTML(fixture(slug, name))
  end

  def test_kairo_mines_the_text_prose_after_the_title
    row = html('kairo').at_css('article[id^="kultur_"]')
    text = Scrapers::Kairo.new.event_genre_prose(row)

    assert_includes text, 'Musikförderung'      # blurb prose is captured...
    refute_includes text, 'Meet the Pros'        # ...but the h2 title is not
  end

  def test_helsinki_mines_the_description_block
    row = html('helsinki').at_css('div.event')
    text = Scrapers::Helsinki.new.event_genre_prose(row)

    assert_includes text, 'Film'
  end

  def test_bad_bonn_mines_the_detail_article_prose
    detail = html('bad_bonn', 'detail.html')
    text = Scrapers::BadBonn.new.event_genre_prose(detail)

    assert_includes text, 'Shoegaze'
    assert_includes text, 'Slowcore'
  end

  def test_volkshaus_mines_the_collapse_panel_prose
    row = html('volkshaus').at_css('#programmliste .tableitem.event')
    text = Scrapers::Volkshaus.new.event_genre_prose(row)

    assert_includes text, 'Jazzgeschichte'
  end

  def test_rote_fabrik_mines_and_strips_the_html_description
    row = JSON.parse(fixture('rote_fabrik', 'list.html')).values.first
    text = Scrapers::RoteFabrik.new.event_genre_prose(row)

    assert_includes text, 'experimental music' # the prose survives...
    refute_includes text, '<p'                  # ...with its HTML markup stripped
  end

  # The musicradar "Stil:" line is venue prose (commas don't make it a token list),
  # so it's mined match-only rather than minted — and the walk must stop at the next
  # <strong>, never bleeding the "Aktuell:" section into the genre text.
  def test_bierhuebeli_mines_the_musicradar_stil_line_only
    row  = JSON.parse(fixture('bierhuebeli', 'list.html'))
             .find { |r| r['link'].to_s.include?('best-of-2000er-party-september') }
    text = Scrapers::Bierhuebeli.new.event_genre_prose(row)

    assert_includes text, 'Heartbeat-Faktor' # the Stil prose is captured...
    refute_includes text, 'kollektiver'       # ...but the next section (Aktuell:) is not
  end
end
