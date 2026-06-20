require 'test_helper'

# Locks the Schüür date parser independent of the big captured fixture.
#
# Schüür emits dates in several shapes the original single-regex parser got
# wrong or choked on:
#
#   * abbreviated months WITH a trailing dot ("Do. 06. Aug. 2026 – 21:00") —
#     the old code passed "Aug." straight to Time.zone.parse, which silently
#     dropped the day and pinned every such event to the 1st of the month;
#   * months it had no number for ("Okt.", "Dez.") fell through to a bogus parse
#     that raised "argument out of range" and aborted that event;
#   * multi-day ranges ("Fr. 11. – So. 13. Juni 2026 – 20:00") let the range's
#     trailing weekday masquerade as the month and lost the year;
#   * genuine non-dates ("Diverse Daten") with no day/month/year at all.
#
# The fix parses each field with its own anchored pattern and, for a truly
# unparseable row, skips it with a warn (via #skip_row?) instead of raising and
# taking the rest of the venue's programme down. These are SYNTHETIC dates — no
# real taxonomy — asserting the parse mechanics, not catalogue content.
class Scrapers::SchueuerTest < Minitest::Test
  # day-shaped string => expected "YYYY-MM-DD HH:MM" (nil = should not parse)
  PARSEABLE = {
    'Do. 11. Juni 2026 – 21:00'             => '2026-06-11 21:00', # full month
    'Mi. 01. Juli 2026 – 17:00'             => '2026-07-01 17:00',
    'Do. 06. Aug. 2026 – 21:00'             => '2026-08-06 21:00', # abbrev + dot
    'Do. 08. Okt. 2026 – 19:00'             => '2026-10-08 19:00', # abbrev that old code raised on
    'Mo. 29. Dez. 2026 – 19:00'             => '2026-12-29 19:00',
    'Do. 5. März 2026 – 20:00'              => '2026-03-05 20:00', # single-digit day + umlaut month
    'Fr. 11. – So. 13. Juni 2026 – 20:00'   => '2026-06-11 20:00', # day range → start day
    '11.–13. Juli 2026'                     => '2026-07-11 00:00'  # compact range, no time
  }.freeze

  UNPARSEABLE = [
    'Diverse Daten',          # no day/month/year at all
    'Demnächst',              # placeholder
    '32. Juni 2026 – 20:00',  # day out of range — old code raised "argument out of range"
    'Sa. 11. Foobar 2026',    # unknown month word
    ''
  ].freeze

  def test_parses_every_real_date_shape
    PARSEABLE.each do |raw, expected|
      time = scraper.send(:parse_start_time, raw)
      refute_nil time, "expected #{raw.inspect} to parse"
      assert_equal expected, time.strftime('%Y-%m-%d %H:%M'),
                   "wrong start time for #{raw.inspect}"
    end
  end

  def test_returns_nil_for_unparseable_dates
    UNPARSEABLE.each do |raw|
      assert_nil scraper.send(:parse_start_time, raw),
                 "expected #{raw.inspect} NOT to parse"
    end
  end

  # The whole point of the bug: an unparseable row must be skipped + logged at
  # warn (with the offending value) — never raise out of the loop and abort the
  # rest of the programme.
  def test_skip_row_warns_and_skips_unparseable_without_raising
    logged = nil
    fake_logger = Object.new
    fake_logger.define_singleton_method(:warn) { |msg| logged = msg }

    Rails.stub(:logger, fake_logger) do
      assert scraper.send(:skip_row?, row_with_date('Diverse Daten')),
             'expected an unparseable-date row to be skipped'
    end

    assert_match(/Schüür/, logged)
    assert_match(/Diverse Daten/, logged, 'warn message should include the offending value')
  end

  def test_skip_row_keeps_good_rows
    refute scraper.send(:skip_row?, row_with_date('Do. 11. Juni 2026 – 21:00')),
           'a normally-dated row must not be skipped'
  end

  # End-to-end through the template method: a programme with one bad row between
  # two good ones yields exactly the two good events, no raise.
  def test_process_events_skips_bad_row_and_keeps_good_ones
    captured = run_offline(<<~HTML)
      #{event_box('Good A', 'Do. 11. Juni 2026 – 21:00', '/events/good-a')}
      #{event_box('Bad Row', 'Diverse Daten',            '/events/bad')}
      #{event_box('Good B', 'Do. 08. Okt. 2026 – 19:00', '/events/good-b')}
    HTML

    titles = captured.map(&:title)
    assert_equal %w[Good\ A Good\ B], titles
    assert_equal '2026-06-11 21:00', captured.first.start_time.strftime('%Y-%m-%d %H:%M')
    assert_equal '2026-10-08 19:00', captured.last.start_time.strftime('%Y-%m-%d %H:%M')
  end

  private

  def scraper
    @scraper ||= Scrapers::Schueuer.new
  end

  def row_with_date(date_text)
    page_from(event_box('Synthetic', date_text, '/events/x')).at_css('.viz-event-list-box')
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
      URI('https://www.schuur.ch/programm'),
      { 'content-type' => 'text/html; charset=utf-8' },
      "<html><body>#{html}</body></html>", '200', Mechanize.new
    )
  end

  # Drive #process_events fully offline (no network, no DB) the same way the
  # golden harness does, capturing the events it would have built.
  Capture = Struct.new(:url) do
    def new_record? = true
    def id = nil
    def dismissed? = false
    def overridden?(_field) = false
    def save! = nil
    attr_accessor :start_time, :start_date, :title, :subtitle,
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
