module CapturesHelper
  def place_suggestions(candidate)
    return [] if candidate.place.blank?

    named = Fingerprint.for(candidate.place)
    suggestions = PlaceSuggester.for_name(candidate.place, url: candidate.source_url)
    return [] if suggestions.any? { |suggestion| Fingerprint.for(suggestion.name) == named }

    suggestions
  end

  def place_chips(suggestions, controller)
    suggestions.map do |suggestion|
      suggestion_chip(suggestion.name, controller,
                      action: "#{controller}#applySuggestion", name: suggestion.name,
                      locality: suggestion.locality, canton: suggestion.canton)
    end
  end

  def locality_chips(suggestions, candidate, controller)
    suggestions.select { |suggestion| suggestion.locality.present? }
               .uniq { |suggestion| Fingerprint.for(suggestion.locality) }
               .reject { |suggestion| changes_nothing?(suggestion, candidate) }
               .map do |suggestion|
                 suggestion_chip(suggestion.locality, controller,
                                 action: "#{controller}#applyLocality",
                                 locality: suggestion.locality, canton: suggestion.canton)
               end
  end

  def changes_nothing?(suggestion, candidate)
    Fingerprint.for(suggestion.locality) == Fingerprint.for(candidate.locality) &&
      suggestion.canton == candidate.canton
  end

  def suggestion_chip(label, controller, action:, **params)
    data = params.compact.transform_keys { |name| "#{controller}_#{name}_param".tr("-", "_") }
    { label: label, attrs: { data: data.merge(action: action) } }
  end

  def capture_duplicates(candidate)
    EventCapture::DuplicateFinder.for(title: candidate.title, date: candidate.date,
                                      place: candidate.place, locality: candidate.locality)
  end

  def capture_matches(events, read)
    events.map do |event|
      { id: event.id, title: event.title, meta: capture_match_meta(event),
        adds: capture_match_adds(event, read) }
    end
  end

  def capture_match_meta(event)
    [event.start_time&.strftime("%H:%M"), event.venue&.name].compact_blank.join(" · ")
  end

  def capture_match_adds(event, read)
    parts = []
    parts << t("capture.matches.fields.description") if read[:description].present? && event.description.blank?
    parts << t("capture.matches.fields.time") if read[:time].present? && event.start_time.blank?
    genres = capture_new_genres(event, read[:genres])
    parts << t("capture.matches.fields.genres", count: genres.size) if genres.any?

    parts.any? ? t("capture.matches.adds", fields: parts.join(", ")) : t("capture.matches.nothing")
  end

  def capture_new_genres(event, genres)
    known = event.genre_list.map { |name| Genre.fingerprint_for(name) }.to_set
    Array(genres).compact_blank.reject { |name| known.include?(Genre.fingerprint_for(name)) }
  end

  def capture_localities = Locality.cantons_by_name

  def capture_places = PlaceSuggester.by_name

  def proposed_fields(candidate)
    { "title" => candidate.title, "date" => candidate.date, "time" => candidate.time,
      "place" => candidate.place, "locality" => candidate.locality, "canton" => candidate.canton,
      "genres" => candidate.genres.join(", ") }
  end

  def cited_evidence(candidate, field)
    return if candidate.public_send(field).blank?

    candidate.public_send(:"#{field}_evidence")
  end

  def capture_found_titles
    { one: t("capture.review.title", count: 1),
      other: t("capture.review.title", count: "%{count}") }
  end

  def capture_done_flashes
    { zero: t("capture.queue.done", count: 0),
      one: t("capture.queue.done", count: 1),
      other: t("capture.queue.done", count: "%{count}") }
  end

  def canton_options
    Location::CANTON_CODES.sort.map { |code| ["#{code} — #{Location.canton_name(code)}", code] }
  end
end
