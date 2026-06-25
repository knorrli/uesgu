module Admin
  # Read-only discovery inbox: venues an aggregator (e.g. Bewegungsmelder) surfaced
  # that are NOT approved in the registry (VenueLead), ranked by upcoming-event
  # demand. Approving one is a config/venues.yml edit (a PR), so this view is
  # informational — it tells you what's worth approving, not a button that mutates.
  class VenueLeadsController < BaseController
    def index
      @leads = VenueLead.by_demand
    end
  end
end
