require_relative '../../db_test_helper'

# DB-backed coverage that a scraper now collects ALL its genres: both the
# structured field (event_genres) and freetext-mined tokens
# (event_consumption_genres) mint taxonomy, with no closed-vocab gate. An
# unrecognised token lands as a fresh (unplaced) Genre row for the curation
# queue rather than being dropped at ingest. Synthetic taxonomy only.
class Scrapers::ConsumptionGenresTest < ActiveSupport::TestCase
  include TaxonomyFixtures

  # A minimal named scraper exposing the two genre buckets for a single event,
  # with the other field extractors stubbed so build_event can run offline. Named
  # (not anonymous) because Registerable's `inherited` hook reads the class name.
  class StubScraper < Scrapers::Agent
    def self.location = 'Testville'
    def self.locations = %w[Testville Bern BE]
    def self.url = URI.parse('https://fixture.test/')

    attr_accessor :trusted_genres, :consumption_genres

    def event_content(row) = row
    def event_start_time(_content) = Time.zone.local(2030, 1, 1, 20, 0)
    def event_title(_content) = 'Synthetic Show'
    def event_subtitle(_content) = nil
    def event_genres(_content) = Array(@trusted_genres)
    def event_consumption_genres(_content) = Array(@consumption_genres)
  end
  # Keep this test-only scraper out of the global registry so the golden suite
  # (which iterates Scrapers::All) doesn't pick it up.
  Scrapers::All.scrapers.delete('StubScraper')

  def scraper(trusted:, consumption:)
    StubScraper.new.tap do |s|
      s.trusted_genres = trusted
      s.consumption_genres = consumption
    end
  end

  def build
    event = Event.new(url: "https://fixture.test/#{TaxonomyFixtures.next_seq}", title: 'x',
                      start_date: Date.new(2030, 1, 1))
    yield(event)
    event
  end

  def fingerprints(list) = list.map { |name| Genre.fingerprint_for(name) }

  test 'structured (event_genres) tokens are collected and mint new vocabulary' do
    before = Genre.count

    event = build { |e| scraper(trusted: ['Brand New Genre'], consumption: []).send(:build_event, e, :row) }

    assert_includes fingerprints(event.genre_list), Genre.fingerprint_for('Brand New Genre')
    assert_equal before + 1, Genre.count
  end

  test 'freetext (event_consumption_genres) tokens are now collected and mint too — no closed-vocab gate' do
    known = genre(name: 'blues')
    before = Genre.count

    event = build do |e|
      scraper(trusted: [], consumption: [known.name, 'Salsa Namá']).send(:build_event, e, :row)
    end

    # The already-known token AND the brand-new freetext token both attach...
    assert_includes fingerprints(event.genre_list), known.fingerprint
    assert_includes fingerprints(event.genre_list), Genre.fingerprint_for('Salsa Namá')
    # ...and the unrecognised one mints a fresh row (lands unplaced for curation).
    assert_equal before + 1, Genre.count, 'a new freetext token now mints a Genre'
    assert Genre.exists?(fingerprint: Genre.fingerprint_for('Salsa Namá'))
  end

  test 'both buckets are collected together and mint their new tokens' do
    known = genre(name: 'rock')
    before = Genre.count

    event = build do |e|
      scraper(trusted: ['Fresh Discovery'], consumption: [known.name, 'Mined Token']).send(:build_event, e, :row)
    end

    fps = fingerprints(event.genre_list)
    assert_includes fps, Genre.fingerprint_for('Fresh Discovery') # structured → minted
    assert_includes fps, known.fingerprint                        # freetext, already known → matched
    assert_includes fps, Genre.fingerprint_for('Mined Token')     # freetext, new → minted
    assert_equal before + 2, Genre.count, 'the two new tokens (structured + freetext) both mint'
  end
end
