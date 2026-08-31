module Admin
  class ScraperCoverageController < BaseController
    def index
      @presenter = ScraperCoveragePresenter.new
    end
  end
end
