module TagsHelper
  def tag_icon_class(context:)
    case context.to_s
    when 'query'
      'ti-search'
    when 'date'
      'ti-calendar'
    when 'styles'
      'ti-music-alt'
    when 'genres'
      'ti-tag'
    when 'locations', 'venue'
      'ti-home'
    when 'city'
      'ti-location-pin'
    when 'canton'
      'ti-map-alt'
    else
      'ti-bolt'
    end
  end

  def available_tags(context:, applied: [])
    ActsAsTaggableOn::Tag
      .where.not(name: applied)
      .joins(:taggings)
      .where(taggings: { context: context, taggable_type: Event.name })
      .select(:name, :context)
      .distinct
      .order(name: :asc)
  end

  # Localized canton display name, e.g. "BE" -> "Bern"/"Berne".
  def canton_name(code)
    t("cantons.#{code}", default: code)
  end

  # Location names in canton > city > venue order (each canton, then its cities,
  # then their venues, alphabetized within each level). Used to sort the filter
  # dropdown. Names not covered by the scraper hierarchy keep their order after.
  def hierarchical_location_names
    Location.hierarchy.sort.flat_map do |canton, cities|
      [canton] + cities.sort.flat_map { |city, venues| [city] + venues.sort }
    end
  end

  # Available location tags ordered by the hierarchy (unknown tags appended A->Z).
  def ordered_location_tags(applied: [])
    order = hierarchical_location_names.each_with_index.to_h
    available_tags(context: :locations, applied: applied)
      .sort_by { |tag| [order[tag.name] || Float::INFINITY, tag.name] }
  end
end
