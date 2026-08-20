module Admin
  # Read-only oversight for the capture funnel's model calls: provider failures, the
  # values the Normalizer refused, and what a human then corrected. There is nothing
  # to trigger or mute here — an extraction happens when a contributor uploads
  # something. `prompt_sha` narrows every number on the page to one prompt version.
  class ExtractionAttemptsController < BaseController
    def index
      @presenter = ExtractionAttemptsPresenter.new(prompt_sha: params[:prompt_sha])
    end
  end
end
