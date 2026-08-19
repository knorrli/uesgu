module CapturesHelper
  # Computed once from what the model extracted rather than live as they type: the
  # extracted name is the one that needs matching, and a debounced lookup would add
  # an endpoint to fix a problem nobody has.
  def place_suggestions(candidate)
    return [] if candidate.place.blank?

    PlaceSuggester.for_name(candidate.place, url: candidate.source_url)
  end

  def capture_localities
    (Venue.in_taxonomy.map(&:locality) + Place.distinct.pluck(:locality)).compact_blank.uniq.sort
  end

  def canton_options
    Location::CANTON_CODES.map { |code| [canton_name(code), code] }.sort_by(&:first)
  end
end
