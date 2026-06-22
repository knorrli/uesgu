# A throwaway Scrapers::Agent subclass for exercising the counting seams offline
# (no HTTP, no fixtures): supply rows via .next_rows and call it. Deregistered
# from Scrapers::All immediately after definition so it never leaks into the real
# nightly sweep or the golden suite, which both iterate the registry.
class CountingScraperHarness < Scrapers::Agent
  class << self
    attr_accessor :next_rows

    def location = 'Test Venue'
    def locations = ['Test Venue']
    def url = 'https://fixture.test/list'
  end

  # No network: the list page is irrelevant because #event_rows is supplied.
  def get(*) = nil

  def event_rows = self.class.next_rows || []
  def event_url(row) = row[:url]
  def event_content(row) = row
  def event_start_time(_content) = Time.zone.local(2030, 1, 1, 20, 0)

  # A row flagged :bad yields a blank title so save! trips the presence
  # validation — the per-event skip path. A :title lets a re-scrape change data.
  def event_title(content) = content[:bad] ? nil : (content[:title] || 'Synthetic Show')

  # A second, independently-varying field — lets a test change one field while
  # holding another, e.g. to prove an admin-locked field survives a re-scrape.
  def event_subtitle(content) = content[:subtitle]

  # Genres straight from the row, so a test can prove an admin-pinned genre list
  # survives a re-scrape (Event#overridden?(:genres)) or that a duplicate-carrying
  # list still makes a no-op re-scrape look unchanged rather than updated.
  def event_genres(content) = content[:genres]
end

Scrapers::All.scrapers.delete('CountingScraperHarness')
