class ScrapeEventsJob < ApplicationJob
  queue_as :events

  def perform(scraper_class:)
    scraper_class.safe_constantize.call
    # Refresh genre usage counts so newly scraped genres surface in the
    # assignment queue ordered by impact.
    Genre.reconcile!
  end
end
