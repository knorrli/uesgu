require_relative '../../db_test_helper'

# DB-backed coverage that a scraper collects ALL its genres and they MINT
# taxonomy, with no closed-vocab gate: whatever a scraper's single `event_genres`
# hook returns — a clean structured field or tokens mined from unstable free text
# — is kept, and an unrecognised token lands as a fresh (unplaced) Genre row for
# the curation queue rather than being dropped at ingest. Synthetic taxonomy only.
class Scrapers::GenreMintingTest < ActiveSupport::TestCase
  include TaxonomyFixtures

  # A minimal named scraper exposing the genre hook for a single event, with the
  # other field extractors stubbed so build_event can run offline. Named (not
  # anonymous) because Registerable's `inherited` hook reads the class name.
  class StubScraper < Scrapers::Agent
    def self.location = 'Testville'
    def self.locations = %w[Testville Bern BE]
    def self.url = URI.parse('https://fixture.test/')

    attr_accessor :genres

    def event_content(row) = row
    def event_start_time(_content) = Time.zone.local(2030, 1, 1, 20, 0)
    def event_title(_content) = 'Synthetic Show'
    def event_subtitle(_content) = nil
    def event_genres(_content) = Array(@genres)
  end
  # Keep this test-only scraper out of the global registry so the golden suite
  # (which iterates Scrapers::All) doesn't pick it up.
  Scrapers::All.scrapers.delete('StubScraper')

  def scraper(genres:)
    StubScraper.new.tap { |s| s.genres = genres }
  end

  def build
    event = Event.new(url: "https://fixture.test/#{TaxonomyFixtures.next_seq}", title: 'x',
                      start_date: Date.new(2030, 1, 1))
    yield(event)
    event
  end

  def fingerprints(list) = list.map { |name| Genre.fingerprint_for(name) }

  test 'a brand-new token is collected and mints new vocabulary' do
    before = Genre.count

    event = build { |e| scraper(genres: ['Brand New Genre']).send(:build_event, e, :row) }

    assert_includes fingerprints(event.genre_list), Genre.fingerprint_for('Brand New Genre')
    assert_equal before + 1, Genre.count
  end

  test 'a known token matches while a new one mints — no closed-vocab gate' do
    known = genre(name: 'blues')
    before = Genre.count

    event = build do |e|
      scraper(genres: [known.name, 'Salsa Namá']).send(:build_event, e, :row)
    end

    # The already-known token AND the brand-new token both attach...
    assert_includes fingerprints(event.genre_list), known.fingerprint
    assert_includes fingerprints(event.genre_list), Genre.fingerprint_for('Salsa Namá')
    # ...and the unrecognised one mints a fresh row (lands unplaced for curation).
    assert_equal before + 1, Genre.count, 'a new token now mints a Genre'
    assert Genre.exists?(fingerprint: Genre.fingerprint_for('Salsa Namá'))
  end
end
