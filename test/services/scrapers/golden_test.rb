require "test_helper"

class Scrapers::GoldenTest < Minitest::Test
  FIXTURE_ROOT = File.expand_path("../../fixtures/scrapers", __dir__)
  SHAPE_B = %w[bad_bonn kofmehl docks boeroem isc kiff nouveau_monde sedel sous_soul neubad muehle_hunziken marians z7].freeze
  CAPTURING = ENV["CAPTURE_GOLDEN"] == "1"
  REFERENCE_DATE = Date.new(2026, 6, 10)

  class Capture
    FIELDS = %i[start_time start_date title description genre_list location_list cancelled_at].freeze
    attr_accessor(*FIELDS, :hidden, :data_source, :rescheduled_at)
    attr_reader :url

    def initialize(url) = @url = url
    def save! = nil

    def new_record? = true
    def id = nil

    def dismissed? = false

    def overridden?(_field) = false

    def hidden_by_genre? = false

    def to_h
      { url: url }.merge(FIELDS.index_with { |field| serialize(field, public_send(field)) })
    end

    private

    def serialize(field, value)
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
    list_path = File.join(dir, "list.html")
    skip "no fixture captured for #{slug}" unless File.exist?(list_path)

    captured = capture_events(klass, slug, dir)
    assert_url_shape(klass, slug, captured)
    actual = captured.map(&:to_h)
    golden_path = File.join(dir, "golden.json")

    if CAPTURING
      File.write(golden_path, "#{JSON.pretty_generate(actual)}\n")
      skip "captured #{actual.size} event(s) for #{slug}"
    else
      assert File.exist?(golden_path), "missing golden for #{slug} — run CAPTURE_GOLDEN=1"
      expected = JSON.parse(File.read(golden_path), symbolize_names: true)
      assert_equal expected, actual, "#{slug}: parse output drifted from the golden baseline"
    end
  end

  def assert_url_shape(klass, slug, captured)
    pattern = klass.event_url_pattern
    return if pattern.nil?

    captured.each do |c|
      assert c.url.present?, "#{slug}: captured an event with a blank URL"
      assert_match pattern, c.url,
                   "#{slug}: event URL #{c.url.inspect} doesn't match expected shape " \
                   "#{pattern.inspect} — a wrong host/path here ships dead links " \
                   "(see Rote Fabrik). Fix event_url, or update event_url_pattern."
    end
  end

  def capture_events(klass, slug, dir)
    list_page = page_from(File.join(dir, "list.html"), klass.url.to_s)
    detail_page = (page_from(File.join(dir, "detail.html"), "https://fixture.test/detail") if SHAPE_B.include?(slug))

    captured = []
    factory = ->(*, **kwargs) { Capture.new(kwargs[:url]).tap { |c| captured << c } }

    Date.stub(:current, REFERENCE_DATE) do
      scraper = klass.new
      scraper.define_singleton_method(:get) { |*| nil }
      scraper.define_singleton_method(:page) { list_page }
      scraper.define_singleton_method(:click) { |*| detail_page } if detail_page
      scraper.define_singleton_method(:ensure_genres_and_visibility) { |event| }
      scraper.define_singleton_method(:mined_genres) { |content| [] }

      Event.stub(:find_or_initialize_by, factory) do
        scraper.send(:process_events)
      end
    end
    captured
  end

  def page_from(path, uri)
    Mechanize::Page.new(URI(uri), { "content-type" => "text/html; charset=utf-8" }, File.binread(path), "200", Mechanize.new)
  end
end
