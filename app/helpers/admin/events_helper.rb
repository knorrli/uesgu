module Admin
  module EventsHelper
    def event_location_tag(event, type)
      event.locations.map(&:name).find { |name| Location.type_for(name) == type }
    end
  end
end
