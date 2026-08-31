module Admin
  class ExtractionAttemptsController < BaseController
    def index
      @presenter = ExtractionAttemptsPresenter.new(prompt_sha: params[:prompt_sha])
    end
  end
end
