module TagsHelper
  # Phosphor weight applied to every icon (the base class the glyph sits on).
  ICON_BASE = 'ph'

  # The Phosphor glyph class for a tag context, without the ICON_BASE weight,
  # e.g. 'ph-house'. Kept separate so JS can swap a single glyph class on an
  # element that already carries ICON_BASE (see style_picker_controller.js).
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

  # The leading icon on an applied-filter chip, derived from its param so the
  # events filter and the rule form render the same glyph for the same kind of
  # token. Locations (l[]) resolve PER-TYPE from the value (canton/city/venue),
  # matching the mobile filter sheet and the dropdown — so a location chip's icon
  # tells you which kind of place it is, not a flat "where" pin.
  FILTER_CHIP_GLYPH = {
    's[]' => 'ph-music-notes',
    'g[]' => 'ph-tag',
    'q[]' => 'ph-magnifying-glass',
    'd[]' => 'ph-calendar-dots'
  }.freeze

  def filter_chip_icon(param, value = nil)
    return tag_icon_class(context: Location.type_for(value)) if param == 'l[]' && value.present?

    "#{ICON_BASE} #{FILTER_CHIP_GLYPH.fetch(param, 'ph-lightning')}"
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

  # How a location tag reads to a human. Cities/venues are stored by name, but a
  # canton tag is its code ("BE"), so localize that one to "Bern"/"Berne". Used by
  # the mobile filter sheet's chips and tree so cantons never surface as raw codes.
  def location_display(name)
    Location.type_for(name) == :canton ? canton_name(name) : name
  end

  # A canton > city > venue tree for the mobile "where" filter sheet, annotated
  # with live event counts. Structure comes from the scraper-derived hierarchy
  # (Location.hierarchy) but every node is pruned to what events actually carry
  # right now (Location.usage), so the sheet never offers a venue with nothing on.
  #
  # Each node: { name:, value:, type:, count:, children: }. A canton filters by
  # its CODE (the tag events carry, e.g. "BE") but is shown by its localized name,
  # so name and value differ there; cities/venues tag by their own name.
  def location_filter_tree
    counts = Location.usage.to_h { |row| [row[:name], row[:count]] }

    Location.hierarchy.sort.filter_map do |canton, cities|
      city_nodes = cities.sort.filter_map do |city, venues|
        venue_nodes = venues.uniq.sort.filter_map do |venue|
          count = counts[venue].to_i
          { name: venue, value: venue, type: :venue, count: count, search: venue } if count.positive?
        end
        next if venue_nodes.empty? && counts[city].to_i.zero?

        { name: city, value: city, type: :city,
          count: counts[city] || venue_nodes.sum { |v| v[:count] },
          search: ([city] + venue_nodes.map { |v| v[:name] }).join(' '), children: venue_nodes }
      end
      next if city_nodes.empty? && counts[canton].to_i.zero?

      name = canton_name(canton)
      { name: name, value: canton, type: :canton,
        count: counts[canton] || city_nodes.sum { |c| c[:count] },
        search: ([name, canton] + city_nodes.flat_map { |c| [c[:name]] + c[:children].map { |v| v[:name] } }).join(' '),
        children: city_nodes }
    end
  end
end
