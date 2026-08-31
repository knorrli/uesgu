class CapturedVenueLeads
  SOURCE = "capture".freeze

  THRESHOLD = 2

  def self.refresh!
    counts = Location.usage.to_h { |row| [row[:name], row[:count]] }

    leads = Place.canonicals.by_name.filter_map do |place|
      count = counts[place.name].to_i
      next if count < THRESHOLD

      next if Venue.matching(place.name)

      { venue: place.name, locality: place.locality, canton: place.canton, event_count: count }
    end

    VenueLead.refresh!(source: SOURCE, leads: leads)
    leads
  end
end
