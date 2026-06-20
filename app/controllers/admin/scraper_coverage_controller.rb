module Admin
  # Scraper data-coverage matrix: per-scraper fill-rates (time / subtitle / genre)
  # computed live from the events each scraper owns. Read-only oversight that
  # surfaces which scrapers leave collectable data on the table — and which broke.
  class ScraperCoverageController < BaseController
    def index
      @presenter = ScraperCoveragePresenter.new
    end
  end
end
