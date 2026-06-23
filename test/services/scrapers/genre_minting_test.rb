require_relative "../../db_test_helper"

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
    def self.location = "Testville"
    def self.locations = %w[Testville Bern BE]
    def self.url = URI.parse("https://fixture.test/")

    attr_accessor :genres, :description

    def event_content(row) = row
    def event_start_time(_content) = Time.zone.local(2030, 1, 1, 20, 0)
    def event_title(_content) = "Synthetic Show"
    def event_description(_content) = nil
    def event_genres(_content) = Array(@genres)
    def event_genre_prose(_content) = @description
  end
  # Keep this test-only scraper out of the global registry so the golden suite
  # (which iterates Scrapers::All) doesn't pick it up.
  Scrapers::All.scrapers.delete("StubScraper")

  def scraper(genres: nil, description: nil)
    StubScraper.new.tap do |s|
      s.genres = genres
      s.description = description
    end
  end

  def build
    event = Event.new(url: "https://fixture.test/#{TaxonomyFixtures.next_seq}", title: "x",
                      start_date: Date.new(2030, 1, 1))
    yield(event)
    event
  end

  def fingerprints(list) = list.map { |name| Genre.fingerprint_for(name) }

  test "a brand-new token is collected and mints new vocabulary" do
    before = Genre.count

    event = build { |e| scraper(genres: ["Brand New Genre"]).send(:build_event, e, :row) }

    assert_includes fingerprints(event.genre_list), Genre.fingerprint_for("Brand New Genre")
    assert_equal before + 1, Genre.count
  end

  test "a known token matches while a new one mints — no closed-vocab gate" do
    known = genre(name: "blues")
    before = Genre.count

    event = build do |e|
      scraper(genres: [known.name, "Salsa Namá"]).send(:build_event, e, :row)
    end

    # The already-known token AND the brand-new token both attach...
    assert_includes fingerprints(event.genre_list), known.fingerprint
    assert_includes fingerprints(event.genre_list), Genre.fingerprint_for("Salsa Namá")
    # ...and the unrecognised one mints a fresh row (lands unplaced for curation).
    assert_equal before + 1, Genre.count, "a new token now mints a Genre"
    assert Genre.exists?(fingerprint: Genre.fingerprint_for("Salsa Namá"))
  end

  # --- Prose mining wired through build_event --------------------------------
  # A genre-less scraper that opts into event_genre_prose gets known genre
  # names mined from the blurb attached at ingest — match-only, minting nothing.

  # Mining matches the STORED name, so these create exact-named genres directly
  # (the genre() helper appends a uniqueness suffix that the prose couldn't name).

  test "a known genre named in the description prose is mined and attached" do
    known = Genre.create!(name: "Zorptronic")
    before = Genre.count

    event = build do |e|
      scraper(description: "a sweaty night of pure zorptronic energy").send(:build_event, e, :row)
    end

    assert_includes fingerprints(event.genre_list), known.fingerprint
    assert_equal before, Genre.count, "mining attaches existing taxonomy, it must not mint"
  end

  test "mining composes with the scrapers own event_genres" do
    structured = Genre.create!(name: "Wubcore")
    mined = Genre.create!(name: "Flarejazz")

    event = build do |e|
      scraper(genres: [structured.name], description: "support act plays flarejazz").send(:build_event, e, :row)
    end

    assert_includes fingerprints(event.genre_list), structured.fingerprint
    assert_includes fingerprints(event.genre_list), mined.fingerprint
  end

  test "an unknown word in the description prose mints nothing" do
    before = Genre.count

    event = build do |e|
      scraper(description: "just some ordinary words about the night").send(:build_event, e, :row)
    end

    assert_empty event.genre_list
    assert_equal before, Genre.count
  end

  test "mining is skipped when an admin has pinned the genre list" do
    Genre.create!(name: "Zorptronic") # would otherwise be mined from the blurb below
    event = Event.create!(url: "https://fixture.test/#{TaxonomyFixtures.next_seq}", title: "x",
                          start_date: Date.new(2030, 1, 1), overridden_fields: ["genres"])
    event.update!(genre_list: ["Handpicked"])

    scraper(description: "a night of pure zorptronic energy").send(:build_event, event, :row)

    # the pinned list survives untouched — neither event_genres nor mining ran
    assert_equal ["Handpicked"], event.genre_list.sort
  end
end
