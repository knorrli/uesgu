require_relative '../../db_test_helper'

# DB-backed coverage for the discovery-vs-consumption split (see
# Scrapers::Agent#build_event and Genre.existing_only). The golden suite runs
# DB-free and stubs the filter, so the actual closed-vocab behaviour — trusted
# genres mint taxonomy, consumption genres match-only and create nothing — is
# proven here against real Genre rows. Synthetic taxonomy only (TaxonomyFixtures).
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

  test 'existing_only keeps fingerprint matches, drops unknowns, and creates nothing' do
    known = genre(name: 'techno')
    before = Genre.count

    kept = Genre.existing_only([known.name, known.name.upcase, 'No Such Genre', '   '])

    assert_equal before, Genre.count, 'existing_only must never create a Genre'
    assert_includes fingerprints(kept), known.fingerprint
    refute_includes fingerprints(kept), Genre.fingerprint_for('No Such Genre')
  end

  test 'consumption genres attach only when already in the vocabulary' do
    known = genre(name: 'blues')
    before = Genre.count

    event = build do |e|
      scraper(trusted: [], consumption: [known.name, 'Salsa Namá', 'Us']).send(:build_event, e, :row)
    end

    assert_includes fingerprints(event.genre_list), known.fingerprint
    refute_includes fingerprints(event.genre_list), Genre.fingerprint_for('Salsa Namá')
    refute_includes fingerprints(event.genre_list), Genre.fingerprint_for('Us')
    assert_equal before, Genre.count, 'a consumption-only source must not mint taxonomy'
  end

  test 'trusted (discovery) genres mint new vocabulary' do
    before = Genre.count

    event = build do |e|
      scraper(trusted: ['Brand New Genre'], consumption: []).send(:build_event, e, :row)
    end

    assert_includes fingerprints(event.genre_list), Genre.fingerprint_for('Brand New Genre')
    assert_equal before + 1, Genre.count
    assert Genre.exists?(fingerprint: Genre.fingerprint_for('Brand New Genre'))
  end

  test 'a mixed scraper mints its trusted genre while filtering its consumption junk' do
    known = genre(name: 'rock')
    before = Genre.count

    event = build do |e|
      scraper(trusted: ['Fresh Discovery'], consumption: [known.name, 'Ch']).send(:build_event, e, :row)
    end

    fps = fingerprints(event.genre_list)
    assert_includes fps, Genre.fingerprint_for('Fresh Discovery') # trusted → minted
    assert_includes fps, known.fingerprint                        # consumption → matched
    refute_includes fps, Genre.fingerprint_for('Ch')              # consumption junk → dropped
    assert_equal before + 1, Genre.count, 'only the one trusted genre is created'
  end
end
