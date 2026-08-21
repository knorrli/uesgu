module CapturesHelper
  # Computed once from what the model extracted rather than live as they type: the
  # extracted name is the one that needs matching, and a debounced lookup would add
  # an endpoint to fix a problem nobody has.
  def place_suggestions(candidate)
    return [] if candidate.place.blank?

    PlaceSuggester.for_name(candidate.place, url: candidate.source_url)
  end

  # Tapping one takes a spelling the app already has instead of minting a variant —
  # see PlaceSuggester for what a split venue name costs.
  def place_chips(suggestions)
    suggestions.map do |suggestion|
      suggestion_chip(suggestion.name, action: "capture#applySuggestion",
                      capture_name_param: suggestion.name,
                      capture_locality_param: suggestion.locality,
                      capture_canton_param: suggestion.canton)
    end
  end

  # The towns those same venues sit in, which is the only ranking the locality field
  # has to offer. Every locality the app knows is far too many to render and
  # alphabetical order ranks nothing; the places already being suggested are few, and
  # they are about this poster. The long tail stays reachable through the datalist.
  def locality_chips(suggestions)
    suggestions.select { |suggestion| suggestion.locality.present? }
               .uniq { |suggestion| Fingerprint.for(suggestion.locality) }
               .map do |suggestion|
                 suggestion_chip(suggestion.locality, action: "capture#applyLocality",
                                 capture_locality_param: suggestion.locality,
                                 capture_canton_param: suggestion.canton)
               end
  end

  def suggestion_chip(label, **data) = { label: label, attrs: { data: data } }

  # Name => canton, off the same rows that compute the canton at extraction. The
  # datalist offers the names and the card fills the canton from the map when one is
  # picked, so both halves of the field answer from one place.
  def capture_localities = Locality.cantons_by_name

  # What the model proposed, keyed the way the form posts it, so the card can carry it
  # back for the diff. Mirrors the visible inputs exactly — a value that renders one
  # way and is proposed another reads as a correction nobody made.
  def proposed_fields(candidate)
    { "title" => candidate.title, "date" => candidate.date, "time" => candidate.time,
      "place" => candidate.place, "locality" => candidate.locality, "canton" => candidate.canton,
      "genres" => candidate.genres.join(", ") }
  end

  # The model's verbatim quote for a field, and only where that field HAS a value: a
  # candidate can carry evidence for a value the normalizer nulled, and a quote under
  # an empty field reads as a value being withheld rather than as one refused.
  def cited_evidence(candidate, field)
    return if candidate.public_send(field).blank?

    candidate.public_send(:"#{field}_evidence")
  end

  def canton_options
    Location::CANTON_CODES.map { |code| [canton_name(code), code] }.sort_by(&:first)
  end
end
