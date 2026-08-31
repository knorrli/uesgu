module CapturesHelper
  # Computed once from what the model extracted rather than live as they type: the
  # extracted name is the one that needs matching, and a debounced lookup would add
  # an endpoint to fix a problem nobody has.
  #
  # A name the app already carries verbatim empties the row rather than heading it: an
  # exact hit settles "did you mean one of these?", so the near-misses beside it answer
  # a question nobody is asking any more. The towns go with them — locality_chips reads
  # this same list, and the town in the field is that venue's own.
  def place_suggestions(candidate)
    return [] if candidate.place.blank?

    named = Fingerprint.for(candidate.place)
    suggestions = PlaceSuggester.for_name(candidate.place, url: candidate.source_url)
    return [] if suggestions.any? { |suggestion| Fingerprint.for(suggestion.name) == named }

    suggestions
  end

  # Tapping one takes a spelling the app already has instead of minting a variant —
  # see PlaceSuggester for what a split venue name costs. `controller` is the one the
  # screen mounts: the review queue and hand entry share these fields and nothing else.
  def place_chips(suggestions, controller)
    suggestions.map do |suggestion|
      suggestion_chip(suggestion.name, controller,
                      action: "#{controller}#applySuggestion", name: suggestion.name,
                      locality: suggestion.locality, canton: suggestion.canton)
    end
  end

  # The towns those same venues sit in, which is the only ranking the locality field
  # has to offer. Every locality the app knows is far too many to render and
  # alphabetical order ranks nothing; the places already being suggested are few, and
  # they are about this poster. The long tail stays reachable by typing, which fills
  # the same row from the map below.
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

  # The pair, not the town alone: a chip whose town already matches is still worth a tap
  # while the canton beside it is blank, which is what a town the app does not carry
  # leaves behind (see EventCapture::Normalizer#normalized_canton).
  def changes_nothing?(suggestion, candidate)
    Fingerprint.for(suggestion.locality) == Fingerprint.for(candidate.locality) &&
      suggestion.canton == candidate.canton
  end

  # Stimulus reads a param off `data-<controller>-<name>-param`, so the keys are built
  # rather than written out: the same chip is rendered for two controllers.
  def suggestion_chip(label, controller, action:, **params)
    data = params.compact.transform_keys { |name| "#{controller}_#{name}_param".tr("-", "_") }
    { label: label, attrs: { data: data.merge(action: action) } }
  end

  # Shows we may already carry, looked up from what the model read. Computed here for
  # the same reason place_suggestions is: the extracted values are the ones that need
  # matching, and Creator runs the identical lookup against the EDITED values on the
  # way to publishing, so a card whose date or venue is corrected is still caught.
  def capture_duplicates(candidate)
    EventCapture::DuplicateFinder.for(title: candidate.title, date: candidate.date,
                                      place: candidate.place, locality: candidate.locality)
  end

  # Each match as the card renders it. `read` is what this capture holds, keyed as the
  # card's own fields are — the candidate calls its description a subtitle.
  def capture_matches(events, read)
    events.map do |event|
      { id: event.id, title: event.title, meta: capture_match_meta(event),
        adds: capture_match_adds(event, read) }
    end
  end

  # Enough to tell two shows at one venue apart, which is the whole job here.
  def capture_match_meta(event)
    [event.start_time&.strftime("%H:%M"), event.venue&.name].compact_blank.join(" · ")
  end

  # What answering "it is this one" would actually contribute — named, because
  # otherwise the offer promises an enrichment it may have nothing to make. Only
  # fields the match is MISSING count: CanonicalEnrichment fills blanks and never
  # overwrites, so anything else would be a promise it does not keep.
  def capture_match_adds(event, read)
    parts = []
    parts << t("capture.matches.fields.description") if read[:description].present? && event.description.blank?
    parts << t("capture.matches.fields.time") if read[:time].present? && event.start_time.blank?
    genres = capture_new_genres(event, read[:genres])
    parts << t("capture.matches.fields.genres", count: genres.size) if genres.any?

    parts.any? ? t("capture.matches.adds", fields: parts.join(", ")) : t("capture.matches.nothing")
  end

  # By fingerprint: "Drum & Bass" and "drum and bass" are one tag, so neither counts
  # as something this read would add (see Genre).
  def capture_new_genres(event, genres)
    known = event.genre_list.map { |name| Genre.fingerprint_for(name) }.to_set
    Array(genres).compact_blank.reject { |name| known.include?(Genre.fingerprint_for(name)) }
  end

  # Name => canton, off the same rows that compute the canton at extraction. The card
  # matches the names as they are typed and fills the canton from the same map once one
  # is picked, so both halves of the field answer from one place.
  def capture_localities = Locality.cantons_by_name

  # The venues the same field offers, name => [locality, canton]. Shipped whole rather
  # than looked up as they type, for the reason place_suggestions gives: a second
  # ranking beside the one already rendered can disagree with it, and there are tens of
  # these names, not thousands.
  def capture_places = PlaceSuggester.by_name

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

  # Passing the placeholder itself as the count picks the `other` form and leaves
  # %{count} standing: how many events a batch found, and how many of them went live,
  # is only known in the browser — so every plural form ships to capture_controller.js
  # as a template it fills in.
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
    Location::CANTON_CODES.map { |code| [canton_name(code), code] }.sort_by(&:first)
  end
end
