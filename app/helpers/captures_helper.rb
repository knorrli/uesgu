module CapturesHelper
  # Computed once from what the model extracted rather than live as they type: the
  # extracted name is the one that needs matching, and a debounced lookup would add
  # an endpoint to fix a problem nobody has.
  def place_suggestions(candidate)
    return [] if candidate.place.blank?

    PlaceSuggester.for_name(candidate.place, url: candidate.source_url)
  end

  # Name => canton, off the same lookup that computes the canton at extraction. The
  # datalist offers the names and the card fills the canton from the map when one is
  # picked, so both halves of the field answer from one set of rows.
  def capture_localities = EventCapture::Localities.known.cantons_by_name.sort.to_h

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
