require "test_helper"

# Locks the Z7 mechanics the offline golden can't cover: it stubs `get` to nil, so
# the genre-tag vocabulary is never fetched there and every golden event ships
# genre-less. SYNTHETIC markup and tag terms shaped like the live ones — no real
# programme content.
class Scrapers::Z7Test < Minitest::Test
  def test_tag_slugs_resolve_to_the_venues_own_spelling
    assert_equal ["Zorp/Blorp-Core", "GRB"],
                 genres_for(%w[zorp-blorp-core grb]),
                 "a slug can't be de-slugified back — it has to come from the vocabulary"
  end

  def test_a_slug_missing_from_the_vocabulary_is_dropped_rather_than_guessed
    assert_equal ["GRB"], genres_for(%w[grb never-registered])
  end

  # The related-events strip repeats the same `product_tag-` shape for OTHER shows;
  # reading it would tag every event with its neighbours' genres.
  def test_neighbouring_products_tags_are_not_collected
    html = <<~HTML
      <div id="product-11" class="product product_tag-grb"></div>
      <ul class="related"><li class="product product_tag-zorp-blorp-core"></li></ul>
    HTML
    assert_equal ["GRB"], genres_for_document(html)
  end

  def test_an_unreachable_vocabulary_ships_no_genres_rather_than_the_raw_slugs
    scraper = Scrapers::Z7.new
    scraper.define_singleton_method(:get) { |*| raise Mechanize::ResponseCodeError.new(Struct.new(:code).new("404")) }
    assert_equal [], scraper.event_genres(document_for("zorp-blorp-core"))
  end

  def test_start_time_combines_the_rows_iso_date_with_the_detail_start
    assert_equal "2026-09-04 20:00", start_time_for(detail: meta("Beginn" => "20:00", "Einlass" => "19:00"))
  end

  # Doors sits directly below the start in the same markup, so a scraper reaching
  # for the first clock time in the block would ship every show an hour early.
  def test_doors_time_is_not_mistaken_for_the_start
    assert_equal "2026-09-04 21:30", start_time_for(detail: meta("Einlass" => "20:30", "Beginn" => "21:30"))
  end

  def test_a_start_time_the_page_omits_falls_back_to_midnight
    assert_equal "2026-09-04 00:00", start_time_for(detail: meta("Einlass" => "19:00"))
  end

  # A festival row carries a second <time> for its closing day.
  def test_a_multi_day_row_starts_on_its_first_day
    row = row_for(dates: %w[2026-10-02 2026-10-04])
    assert_equal "2026-10-02 17:00", formatted(scraper_at(row).event_start_time(meta("Beginn" => "17:00")))
  end

  def test_a_row_without_a_date_raises_rather_than_dating_the_event_today
    row = row_for(dates: [])
    error = assert_raises(RuntimeError) { scraper_at(row).event_start_time(meta("Beginn" => "20:00")) }
    assert_match "Zorp Night", error.message
  end

  def test_rows_in_z7s_own_rooms_are_kept_and_a_foreign_hall_is_skipped
    refute Scrapers::Z7.new.skip_row?(row_for(hall: nil)), "the main room badges nothing"
    refute Scrapers::Z7.new.skip_row?(row_for(hall: "Mini Z7")), "the small stage is the same building"
    assert Scrapers::Z7.new.skip_row?(row_for(hall: "Volkshaus Zürich")), "another venue's house"
  end

  private

  VOCABULARY = [
    { "slug" => "zorp-blorp-core", "name" => "Zorp/Blorp-Core" },
    { "slug" => "grb",             "name" => "GRB" }
  ].freeze

  def genres_for(slugs)
    genres_for_document(%(<div id="product-11" class="product #{slugs.map { |s| "product_tag-#{s}" }.join(' ')}"></div>))
  end

  def genres_for_document(html)
    scraper = Scrapers::Z7.new
    scraper.define_singleton_method(:get) { |*| Struct.new(:body).new(JSON.generate(VOCABULARY)) }
    scraper.event_genres(Nokogiri::HTML(html))
  end

  def document_for(*slugs)
    Nokogiri::HTML(%(<div id="product-11" class="product #{slugs.map { |s| "product_tag-#{s}" }.join(' ')}"></div>))
  end

  def start_time_for(detail:)
    formatted(scraper_at(row_for).event_start_time(detail))
  end

  def formatted(time) = time.strftime("%Y-%m-%d %H:%M")

  # `current_row` is the list row the template method is mid-way through; the
  # extractors read the date off it while `content` is the clicked detail page.
  def scraper_at(row)
    Scrapers::Z7.new.tap { |scraper| scraper.instance_variable_set(:@current_row, row) }
  end

  def row_for(dates: ["2026-09-04"], hall: nil)
    html = <<~HTML
      <article>
        #{dates.map { |d| %(<time datetime="#{d}">#{d}</time>) }.join}
        <a href="https://z-7.ch/event/zorp-night/">
          <h2>Zorp Night</h2><p>Blorp Tour</p><h4>The Grbs</h4>
          #{%(<span>#{hall}</span>) if hall}
        </a>
      </article>
    HTML
    Nokogiri::HTML(html).at_css("article")
  end

  def meta(rows)
    html = rows.map { |label, value| "<p><b>#{label}: </b> #{value} </p>" }.join
    Nokogiri::HTML(%(<div class="fooevents-meta"><h3>Eventinfos</h3>#{html}</div>))
  end
end
