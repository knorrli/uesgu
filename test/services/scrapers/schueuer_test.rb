require "test_helper"

class Scrapers::SchueuerTest < Minitest::Test
  PARSEABLE = {
    "Do. 11. Juni 2026 – 21:00"             => "2026-06-11 21:00", #
    "Mi. 01. Juli 2026 – 17:00"             => "2026-07-01 17:00",
    "Do. 06. Aug. 2026 – 21:00"             => "2026-08-06 21:00", #
    "Do. 08. Okt. 2026 – 19:00"             => "2026-10-08 19:00", #
    "Mo. 29. Dez. 2026 – 19:00"             => "2026-12-29 19:00",
    "Do. 5. März 2026 – 20:00"              => "2026-03-05 20:00", # s
    "Fr. 11. – So. 13. Juni 2026 – 20:00"   => "2026-06-11 20:00", # da
    "11.–13. Juli 2026"                     => "2026-07-11 00:00"  #
  }.freeze

  UNPARSEABLE = [
    "Diverse Daten",
    "Demnächst",              #
    "32. Juni 2026 – 20:00",  #
    "Sa. 11. Foobar 2026",
    ""
  ].freeze

  def test_parses_every_real_date_shape
    PARSEABLE.each do |raw, expected|
      time = scraper.send(:parse_start_time, raw)
      refute_nil time, "expected #{raw.inspect} to parse"
      assert_equal expected, time.strftime("%Y-%m-%d %H:%M"),
                   "wrong start time for #{raw.inspect}"
    end
  end

  def test_returns_nil_for_unparseable_dates
    UNPARSEABLE.each do |raw|
      assert_nil scraper.send(:parse_start_time, raw),
                 "expected #{raw.inspect} NOT to parse"
    end
  end

  def test_skip_row_warns_and_skips_unparseable_without_raising
    logged = nil
    fake_logger = Object.new
    fake_logger.define_singleton_method(:warn) { |msg| logged = msg }

    Rails.stub(:logger, fake_logger) do
      assert scraper.send(:skip_row?, row_with_date("Diverse Daten")),
             "expected an unparseable-date row to be skipped"
    end

    assert_match(/Schüür/, logged)
    assert_match(/Diverse Daten/, logged, "warn message should include the offending value")
  end

  def test_skip_row_keeps_good_rows
    refute scraper.send(:skip_row?, row_with_date("Do. 11. Juni 2026 – 21:00")),
           "a normally-dated row must not be skipped"
  end

  def test_process_events_skips_bad_row_and_keeps_good_ones
    captured = run_offline(<<~HTML)
      #{event_box('Good A', 'Do. 11. Juni 2026 – 21:00', '/events/good-a')}
      #{event_box('Bad Row', 'Diverse Daten',            '/events/bad')}
      #{event_box('Good B', 'Do. 08. Okt. 2026 – 19:00', '/events/good-b')}
    HTML

    titles = captured.map(&:title)
    assert_equal %w[Good\ A Good\ B], titles
    assert_equal "2026-06-11 21:00", captured.first.start_time.strftime("%Y-%m-%d %H:%M")
    assert_equal "2026-10-08 19:00", captured.last.start_time.strftime("%Y-%m-%d %H:%M")
  end

  private

  def scraper
    @scraper ||= Scrapers::Schueuer.new
  end

  def row_with_date(date_text)
    page_from(event_box("Synthetic", date_text, "/events/x")).at_css(".viz-event-list-box")
  end

  def event_box(name, date_text, href)
    <<~HTML
      <div class="viz-event-list-box">
        <a class="viz-event-box-details-link" href="#{href}">link</a>
        <div class="viz-event-date">#{date_text}</div>
        <div class="viz-event-name">#{name}</div>
      </div>
    HTML
  end

  def page_from(html)
    Mechanize::Page.new(
      URI("https://www.schuur.ch/programm"),
      { "content-type" => "text/html; charset=utf-8" },
      "<html><body>#{html}</body></html>", "200", Mechanize.new
    )
  end

  Capture = Struct.new(:url) do
    def new_record? = true
    def id = nil
    def dismissed? = false
    def overridden?(_field) = false
    def save! = nil
    attr_accessor :start_time, :start_date, :title, :description,
                  :genre_list, :location_list, :cancelled_at, :rescheduled_at,
                  :hidden, :data_source
  end

  def run_offline(html)
    page = page_from(html)
    captured = []
    factory = ->(*, **kwargs) { Capture.new(kwargs[:url]).tap { |c| captured << c } }

    scraper.define_singleton_method(:get) { |*| nil }
    scraper.define_singleton_method(:page) { page }
    scraper.define_singleton_method(:ensure_genres_and_visibility) { |event| }

    Event.stub(:find_or_initialize_by, factory) do
      scraper.send(:process_events)
    end
    captured
  end
end
