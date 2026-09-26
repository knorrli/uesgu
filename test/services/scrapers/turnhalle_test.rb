require "test_helper"

class Scrapers::TurnhalleTest < Minitest::Test
  def test_follows_the_agenda_chunks_until_there_are_no_more
    scraper = scraper_with(
      first: article(path: "zorp-1/", title: "Zorp"),
      chunks: {
        "100" => { "offset" => "200", "hasmore" => "1", "data" => article(path: "blorp-2/", title: "Blorp") },
        "200" => { "offset" => "300", "hasmore" => "0", "data" => article(path: "grb-3/", title: "Grb") }
      }
    )
    assert_equal %w[Zorp Blorp Grb], scraper.event_rows.map { |row| scraper.event_title(row) }
  end

  def test_a_failed_chunk_keeps_what_was_already_read
    scraper = scraper_with(first: article(path: "zorp-1/"), chunks: {})
    assert_equal 1, scraper.event_rows.size
  end

  def test_only_the_turnhalle_is_kept
    scraper = Scrapers::Turnhalle.new
    refute scraper.skip_row?(row(article(room: "PROGR Turnhalle")))
    assert scraper.skip_row?(row(article(room: "PROGR Aula")))
    assert scraper.skip_row?(row(article(room: nil)))
  end

  def test_a_recurring_event_gets_one_url_per_date
    scraper = scraper_with(
      first: article(path: "loop-7/", date: "2026-10-08") + article(path: "loop-7/", date: "2026-10-15") +
             article(path: "once-8/", date: "2026-10-09")
    )
    assert_equal %w[
      https://www.progr.ch/de/agenda/loop-7/#2026-10-08
      https://www.progr.ch/de/agenda/loop-7/#2026-10-15
      https://www.progr.ch/de/agenda/once-8/
    ], scraper.event_rows.map { |r| scraper.event_url(r) }
  end

  def test_start_time_is_the_first_clock_time_on_the_rows_date
    {
      "22 Uhr" => "22:00",
      "20:30 Uhr" => "20:30",
      "20–22:15 Uhr" => "20:00",
      "" => "00:00"
    }.each do |time, expected|
      start = Scrapers::Turnhalle.new.event_start_time(row(article(date: "2026-10-19", time: time)))
      assert_equal "2026-10-19 #{expected}", start.strftime("%Y-%m-%d %H:%M"), "time #{time.inspect}"
    end
  end

  def test_a_row_without_a_date_raises_rather_than_dating_the_event_today
    assert_raises(RuntimeError) { Scrapers::Turnhalle.new.event_start_time(row(article(date: ""))) }
  end

  def test_the_description_is_the_plain_language_summary_without_its_label
    scraper = Scrapers::Turnhalle.new
    assert_equal "Zorp spielt Blorp.", scraper.event_description(row(article(summary: "Zorp spielt Blorp.")))
    assert_nil scraper.event_description(row(article(summary: nil)))
  end

  def test_categories_become_genres
    assert_equal ["Zorpcore", "Blorp Wave"],
                 Scrapers::Turnhalle.new.event_genres(row(article(categories: "Zorpcore, Blorp Wave")))
  end

  private

  def scraper_with(first:, chunks: {})
    list = Nokogiri::HTML(%(<div id="agendalist" data-g-offset="100">#{first}</div>))
    Scrapers::Turnhalle.new.tap do |scraper|
      scraper.define_singleton_method(:page) { list }
      scraper.define_singleton_method(:get) do |_url, params, *|
        chunk = chunks[params[:offset].to_s]
        Struct.new(:body).new(JSON.generate(chunk)) if chunk
      end
    end
  end

  def row(html) = Nokogiri::HTML(html).at_css("article")

  def article(path: "zorp-1/", title: "Zorp", date: "2026-10-08", time: "20 Uhr",
              room: "PROGR Turnhalle", categories: "Konzert", summary: "Zorp spielt.")
    <<~HTML
      <article class="event" data-g-date="#{date}" data-g-path="#{path}">
        <div class="row"><a href="#">
          <div class="title"><h2><span class="invisible">Do. <br>08.10.</span><span>#{title}</span></h2></div>
          <div class="type">#{%(<span class="venues">#{room}</span>) if room}<span class="categories">#{categories}</span></div>
          <div class="time"><span>#{time}</span></div>
        </a></div>
        <div class="details"><div class="row"><div class="text">
          #{%(<p><strong>Einfach gesagt:</strong> #{summary}</p>) if summary}
          <p>Mehr über Zorp.</p>
        </div></div></div>
      </article>
    HTML
  end
end
