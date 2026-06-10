module TagsHelper
  # Phosphor weight applied to every icon (the base class the glyph sits on).
  ICON_BASE = 'ph'

  # The Phosphor glyph class for a tag context, without the ICON_BASE weight,
  # e.g. 'ph-house'. Kept separate so JS can swap a single glyph class on an
  # element that already carries ICON_BASE (see filter_controller.js).
  def tag_icon_glyph(context:)
    case context.to_s
    when 'query'
      'ph-magnifying-glass'
    when 'date'
      'ph-calendar-dots'
    when 'styles'
      'ph-music-notes'
    when 'genres'
      'ph-tag'
    when 'locations', 'venue'
      'ph-house'
    when 'city'
      'ph-map-pin'
    when 'canton'
      'ph-map-trifold'
    else
      'ph-lightning'
    end
  end

  # Full icon class incl. the Phosphor weight, e.g. 'ph ph-house'.
  def tag_icon_class(context:)
    "#{ICON_BASE} #{tag_icon_glyph(context: context)}"
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
