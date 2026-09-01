require_relative "../../db_test_helper"

class Scrapers::LocationPinningTest < ActiveSupport::TestCase
  include TaxonomyFixtures

  class StubScraper < Scrapers::Agent
    def self.location = "Testville"
    def self.locations = %w[Testville Bern BE]
    def self.url = URI.parse("https://fixture.test/")

    def event_content(row) = row
    def event_start_time(_content) = Time.zone.local(2030, 1, 1, 20, 0)
    def event_title(_content) = "Synthetic Show"
    def event_description(_content) = nil
    def event_genres(_content) = []
  end
  Scrapers::All.scrapers.delete("StubScraper")

  test "a scrape writes the scraper's own locations onto an untouched event" do
    e = event(title: "Fresh")

    StubScraper.new.send(:build_event, e, :row)

    assert_equal %w[BE Bern Testville], e.location_list.sort
  end

  test "a scrape leaves the locations alone once an admin has pinned them" do
    e = event(title: "Pinned")
    e.update!(location_list: %w[Zorpwil BE], overridden_fields: ["locations"])

    StubScraper.new.send(:build_event, e, :row)

    assert_equal %w[BE Zorpwil], e.location_list.sort
  end
end
