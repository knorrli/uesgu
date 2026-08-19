module CapturesHelper
  # Near-name places and registry venues the contributor can tap instead of
  # minting a variant. Computed once from what the model extracted, rather than
  # live as they type: the extracted name is the one that needs matching, and a
  # debounced lookup would add an endpoint to fix a problem nobody has.
  def place_suggestions(candidate)
    return [] if candidate.place.blank?

    PlaceSuggester.for_name(candidate.place, url: candidate.source_url)
  end

  # Every locality the taxonomy knows, from both sources. A suggestion list, not a
  # closed set — decision 6 made this field free text on purpose.
  def capture_localities
    (Venue.in_taxonomy.map(&:locality) + Place.distinct.pluck(:locality)).compact_blank.uniq.sort
  end

  # Canton codes with their localized names, ordered by name — the same closed list
  # of 26 the location taxonomy types against.
  def canton_options
    Location::CANTON_CODES.map { |code| [canton_name(code), code] }.sort_by(&:first)
  end
end
