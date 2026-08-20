module Admin
  # Read-only oversight for the capture funnel's model calls: provider failures and
  # the values the Normalizer refused, over the most recent attempts. There is
  # nothing to trigger or mute here — an extraction happens when a contributor
  # uploads something.
  class ExtractionAttemptsController < BaseController
    def index
      @presenter = ExtractionAttemptsPresenter.new
    end
  end
end
