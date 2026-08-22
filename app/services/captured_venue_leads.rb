# The capture funnel's other output: a captured place that keeps hosting shows is a
# venue worth writing a scraper for, so it is nominated into the VenueLead inbox
# beside the aggregator-sourced leads.
#
# Counted, never classified. "Is this a fixed venue or a one-off?" is a judgment
# about the world outside the poster, which the extraction pipeline refuses to ask of
# a model — and name heuristics ("…fest", "Konzert im …") are the same guess in
# cheaper clothes, across three languages. Repetition IS the definition of a fixed
# venue, and VenueLead.by_demand already ranks on it, so this stays a pure projection
# with no judgment anywhere in it.
class CapturedVenueLeads
  SOURCE = "capture".freeze

  # One event never answers "should we write a scraper for this?"; two is the
  # smallest number that can. Erring low is deliberate: a false positive costs one
  # glance at a list whose whole purpose is being glanced at, while a real venue that
  # is never nominated is silent and costs coverage indefinitely.
  THRESHOLD = 2

  def self.refresh!
    counts = Location.usage.to_h { |row| [row[:name], row[:count]] }

    # Aliases are left out: a merged-away spelling is not a second venue, and its
    # events are already counted under the name it was folded into.
    leads = Place.canonicals.by_name.filter_map do |place|
      count = counts[place.name].to_i
      next if count < THRESHOLD

      # Every disposition, not just the consumed ones — which is what makes a
      # `disposition: reject` row in config/venues.yml the way to say "no thanks" to
      # a nomination. refresh! is delete-and-reinsert, so nothing here can hold that
      # answer, and a capture lead never ages out the way an aggregator one does:
      # its count only grows.
      next if Venue.matching(place.name)

      { venue: place.name, locality: place.locality, canton: place.canton, event_count: count }
    end

    VenueLead.refresh!(source: SOURCE, leads: leads)
    leads
  end
end
