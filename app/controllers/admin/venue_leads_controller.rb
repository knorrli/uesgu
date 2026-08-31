module Admin
  class VenueLeadsController < BaseController
    def index
      @leads = VenueLead.by_demand
    end
  end
end
