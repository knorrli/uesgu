require 'test_helper'

# Behavior-preservation harness for the scraper template-method refactor.
#
# It exercises each scraper's `process_events` against a saved HTML fixture with
# every I/O seam stubbed — `get`/`page`/`click` parse fixtures, `Event` is a plain
# capture object, and `event_styles` echoes its input — so the run is fully offline
# and touches no database. The captured per-event field assignments are compared to
# a committed golden JSON.
#
# Crucially the harness only relies on seams shared by BOTH the old (inline) and new
# (hook-based) scrapers, so the SAME test captures the golden on the pre-refactor
# code and then guards the refactor:
#
#   CAPTURE_GOLDEN=1 bin/rails test test/services/scrapers/golden_test.rb   # write goldens
#   bin/rails test test/services/scrapers/golden_test.rb                    # assert vs goldens
class Scrapers::GoldenTest < Minitest::Test
  FIXTURE_ROOT = File.expand_path('../../fixtures/scrapers', __dir__)
  # Click-into-detail scrapers: a stubbed `click` returns the saved detail page.
  SHAPE_B = %w[bad_bonn kofmehl docks boeroem isc kiff nouveau_monde sedel].freeze
  CAPTURING = ENV['CAPTURE_GOLDEN'] == '1'
  # Pin the clock to when the fixtures were captured so year-inferring scrapers
  # stay deterministic regardless of when the suite runs (ISC reads Date.current
  # to resolve the year its detail pages omit; left live, its golden rots a year
  # later). This is the only clock dependency in golden output.
  REFERENCE_DATE = Date.new(2026, 6, 10)

  # Stand-in for an Event that records field assignments instead of persisting.
  class Capture
    FIELDS = %i[start_time start_date title subtitle genre_list style_list location_list cancelled_at].freeze
    attr_accessor(*FIELDS, :hidden)
    attr_reader :url

    def initialize(url) = @url = url
    def save! = nil

    # process_events now branches on new_record? to tally created-vs-updated and
    # collect created ids. The offline run never persists, so every capture reads
    # as a brand-new record with no id — neither feeds the golden output.
    def new_record? = true
    def id = nil

    # Offline captures are never dismissed (no DB) — the scraper's dismissed-skip
    # guard must read as false here.
    def dismissed? = false

    # Visibility is a DB-derived projection (Genre.hidden), not a parsing concern,
    # so the offline run treats every event as visible — mirroring the stubbed
    # event_styles. The real derivation is covered by EventTest.
    def hidden_by_genre? = false

    def to_h
      { url: url }.merge(FIELDS.index_with { |field| serialize(field, public_send(field)) })
    end

    private

    def serialize(field, value)
      # cancelled_at is a wall-clock timestamp; record only its presence so the
      # golden stays deterministic while still proving detection fired.
      return !value.nil? if field == :cancelled_at

      value.respond_to?(:iso8601) ? value.iso8601 : value
    end
  end

  Scrapers::All.scrapers.each_key do |demodulized|
    slug = demodulized.underscore
    define_method("test_#{slug}_matches_golden") do
      run_golden(Scrapers::All.scrapers[demodulized], slug)
    end
  end

  private

  def run_golden(klass, slug)
    dir = File.join(FIXTURE_ROOT, slug)
    list_path = File.join(dir, 'list.html')
    skip "no fixture captured for #{slug}" unless File.exist?(list_path)

    captured = capture_events(klass, slug, dir)
    actual = captured.map(&:to_h)
    golden_path = File.join(dir, 'golden.json')

    if CAPTURING
      File.write(golden_path, "#{JSON.pretty_generate(actual)}\n")
      skip "captured #{actual.size} event(s) for #{slug}"
    else
      assert File.exist?(golden_path), "missing golden for #{slug} — run CAPTURE_GOLDEN=1"
      expected = JSON.parse(File.read(golden_path), symbolize_names: true)
      assert_equal expected, actual, "#{slug}: parse output drifted from the golden baseline"
    end
  end

  def capture_events(klass, slug, dir)
    list_page = page_from(File.join(dir, 'list.html'), klass.url.to_s)
    detail_page = (page_from(File.join(dir, 'detail.html'), 'https://fixture.test/detail') if SHAPE_B.include?(slug))

    captured = []
    factory = ->(*, **kwargs) { Capture.new(kwargs[:url]).tap { |c| captured << c } }

    Date.stub(:current, REFERENCE_DATE) do
      scraper = klass.new
      scraper.define_singleton_method(:get) { |*| nil }
      scraper.define_singleton_method(:page) { list_page }
      scraper.define_singleton_method(:click) { |*| detail_page } if detail_page
      # Keep the run DB-free: style mapping is not under test, so echo the genres.
      scraper.define_singleton_method(:event_styles) { |genres:| Array(genres) }

      # build_event filters consumption genres against existing rows; the closed-
      # vocab behaviour is covered DB-backed elsewhere, so here echo (parse-only).
      Event.stub(:find_or_initialize_by, factory) do
        Genre.stub(:existing_only, ->(names) { Array(names) }) do
          scraper.send(:process_events)
        end
      end
    end
    captured
  end

  def page_from(path, uri)
    Mechanize::Page.new(URI(uri), { 'content-type' => 'text/html; charset=utf-8' }, File.binread(path), '200', Mechanize.new)
  end
end
