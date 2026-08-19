module TagsHelper
  # Phosphor weight applied to every icon (the base class the glyph sits on).
  ICON_BASE = "ph"

  # The Phosphor glyph class for a tag context, without the ICON_BASE weight,
  # e.g. 'ph-house'. Kept separate so JS can swap a single glyph class on an
  # element that already carries ICON_BASE.
  def tag_icon_glyph(context:)
    case context.to_s
    when "query"
      "ph-magnifying-glass"
    when "date"
      "ph-calendar-dots"
    when "genres"
      "ph-tag"
    when "locations", "venue"
      "ph-house"
    when "locality"
      "ph-map-pin"
    when "canton"
      "ph-map-trifold"
    else
      "ph-lightning"
    end
  end

  # Full icon class incl. the Phosphor weight, e.g. 'ph ph-house'.
  def tag_icon_class(context:)
    "#{ICON_BASE} #{tag_icon_glyph(context: context)}"
  end

  # The leading icon on an applied-filter chip, derived from its param so the
  # events filter and the rule form render the same glyph for the same kind of
  # token. Freetext + genre (q[]) share the search glyph. Locations (l[]) resolve
  # PER-TYPE from the value (canton/locality/venue), so a location chip's icon tells
  # you which kind of place.
  FILTER_CHIP_GLYPH = {
    "q[]" => "ph-magnifying-glass",
    "d[]" => "ph-calendar-dots"
  }.freeze

  def filter_chip_icon(param, value = nil)
    return tag_icon_class(context: Location.type_for(value)) if param == "l[]" && value.present?

    "#{ICON_BASE} #{FILTER_CHIP_GLYPH.fetch(param, 'ph-lightning')}"
  end

  # The turbo-frame holding a filter sheet's option tree. One home for the id, so
  # the placeholder frame in the sheet and the one the response wraps its rows in
  # can't drift apart (a mismatch would blank the frame — and with it the applied
  # values it holds until the tree lands).
  def filter_sheet_frame_id(field)
    "filter_sheet_#{field}"
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

  # The curated genre tree for the "what" filter, shaped exactly like
  # location_filter_tree so the What and Where pickers render through the same
  # markup. Roots → children → grandchildren (the tree maxes at 3 levels, mapping
  # onto canton → locality → venue), each annotated with a subtree event count and a
  # search blob. Pruned to subtrees that carry events right now, and to genuine
  # roots (a top-level genre with children) so the unplaced queue backlog stays
  # out. Filtering by any node matches it + its descendants (see
  # Filter#expanded_genre_names), so a node's `value` is just its own name.
  #
  # Each node: { name:, value:, count:, search:, children: }.
  def genre_filter_tree
    genres = Genre.where(hidden_at: nil, blocked_at: nil, ignored_at: nil, canonical_id: nil)
                  .by_name.to_a
    children_of = genres.group_by(&:parent_id)
    (children_of[nil] || []).filter_map do |root|
      next unless children_of.key?(root.id) # skip unplaced (childless) top-level genres

      genre_filter_node(root, children_of)
    end
  end

  # One genre_filter_tree node, built depth-first. Returns nil for an empty
  # subtree (no events anywhere beneath it) so the picker never offers a dead end.
  def genre_filter_node(genre, children_of)
    child_nodes = (children_of[genre.id] || []).filter_map { |child| genre_filter_node(child, children_of) }
    count = genre.events_count + child_nodes.sum { |node| node[:count] }
    return nil if count.zero?

    { name: genre.name, value: genre.name, count: count,
      search: ([genre.name] + child_nodes.map { |node| node[:search] }).join(" "),
      children: child_nodes }
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

  # A canton > locality > venue tree for the mobile "where" filter sheet, annotated
  # with live event counts. Structure comes from the scraper-derived hierarchy
  # (Location.hierarchy) but every node is pruned to what events actually carry
  # right now (Location.usage), so the sheet never offers a venue with nothing on.
  #
  # Each node: { name:, value:, type:, count:, children: }. A canton filters by
  # its CODE (the tag events carry, e.g. "BE") but is shown by its localized name,
  # so name and value differ there; localities/venues tag by their own name.
  def location_filter_tree
    counts = Location.usage.to_h { |row| [row[:name], row[:count]] }

    Location.hierarchy.sort.filter_map do |canton, localities|
      locality_nodes = localities.sort.filter_map do |locality, venues|
        venue_nodes = venues.uniq.sort.filter_map do |venue|
          count = counts[venue].to_i
          { name: venue, value: venue, type: :venue, count: count, search: venue } if count.positive?
        end
        next if venue_nodes.empty? && counts[locality].to_i.zero?

        { name: locality, value: locality, type: :locality,
          count: counts[locality] || venue_nodes.sum { |v| v[:count] },
          search: ([locality] + venue_nodes.map { |v| v[:name] }).join(" "), children: venue_nodes }
      end
      next if locality_nodes.empty? && counts[canton].to_i.zero?

      name = canton_name(canton)
      { name: name, value: canton, type: :canton,
        count: counts[canton] || locality_nodes.sum { |c| c[:count] },
        search: ([name, canton] + locality_nodes.flat_map { |c| [c[:name]] + c[:children].map { |v| v[:name] } }).join(" "),
        children: locality_nodes }
    end
  end
end
