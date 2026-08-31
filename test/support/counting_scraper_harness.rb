class CountingScraperHarness < Scrapers::Agent
  class << self
    attr_accessor :next_rows

    def location = "Test Venue"
    def locations = ["Test Venue"]
    def url = "https://fixture.test/list"
  end

  def get(*) = nil

  def event_rows = self.class.next_rows || []
  def event_url(row) = row[:url]
  def event_content(row) = row
  def event_start_time(_content) = Time.zone.local(2030, 1, 1, 20, 0)

  def event_title(content) = content[:bad] ? nil : (content[:title] || "Synthetic Show")

  def event_description(content) = content[:description]

  def event_genres(content) = content[:genres]
end

Scrapers::All.scrapers.delete("CountingScraperHarness")
