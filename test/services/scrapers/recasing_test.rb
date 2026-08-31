require_relative "../../db_test_helper"

# Several venue sites set their whole programme in capitals, so the text a scraper
# reads faithfully still shouts. Recasing sits in build_event rather than in each
# scraper, which is what this covers: the rule reaches every source at once, and it
# yields to an admin's edit like every other re-derived field.
class Scrapers::RecasingTest < ActiveSupport::TestCase
  include TaxonomyFixtures

  # Named (not anonymous) because Registerable's `inherited` hook reads the class
  # name, and kept out of the registry so the golden suite does not pick it up.
  class StubScraper < Scrapers::Agent
    def self.location = "Testville"
    def self.locations = %w[Testville Bern BE]
    def self.url = URI.parse("https://fixture.test/")

    attr_accessor :title, :description

    def event_content(row) = row
    def event_start_time(_content) = Time.zone.local(2030, 1, 1, 20, 0)
    def event_title(_content) = @title
    def event_description(_content) = @description
    def event_genres(_content) = []
  end
  Scrapers::All.scrapers.delete("StubScraper")

  def scraped(title:, description: nil, **event_attrs)
    scraper = StubScraper.new
    scraper.title = title
    scraper.description = description
    event = Event.new({ url: "https://fixture.test/#{TaxonomyFixtures.next_seq}",
                        title: "x", start_date: Date.new(2030, 1, 1) }.merge(event_attrs))
    scraper.send(:build_event, event, :row)
    event
  end

  test "a shouted title is restyled on the way in" do
    assert_equal "Michael Schenker Group", scraped(title: "MICHAEL SCHENKER GROUP").title
  end

  test "a shouted description is restyled on the way in" do
    event = scraped(title: "Curtis Harding", description: "EIN ABEND MIT FREUNDEN")

    assert_equal "Ein Abend Mit Freunden", event.description
  end

  test "a title the source did not shout arrives as it was published" do
    assert_equal "LEYA + Junge Eko", scraped(title: "LEYA + Junge Eko").title
  end

  test "a lone shouted word is left standing" do
    assert_equal "KMFDM", scraped(title: "KMFDM").title
  end

  # The recaser runs where the scraper decides the field, so it is behind the same
  # guard: an admin who fixed the casing by hand keeps their version.
  test "a locked title is not restyled" do
    event = scraped(title: "MICHAEL SCHENKER GROUP", overridden_fields: ["title"])

    assert_equal "x", event.title
  end
end
