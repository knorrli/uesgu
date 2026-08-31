module TagsHelper
  ICON_BASE = "ph"

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

  def tag_icon_class(context:)
    "#{ICON_BASE} #{tag_icon_glyph(context: context)}"
  end

  FILTER_CHIP_GLYPH = {
    "q[]" => "ph-magnifying-glass",
    "d[]" => "ph-calendar-dots"
  }.freeze

  def filter_chip_icon(param, value = nil)
    return tag_icon_class(context: Location.type_for(value)) if param == "l[]" && value.present?

    "#{ICON_BASE} #{FILTER_CHIP_GLYPH.fetch(param, 'ph-lightning')}"
  end

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

  def genre_filter_tree
    genres = Genre.where(hidden_at: nil, blocked_at: nil, ignored_at: nil, canonical_id: nil)
                  .by_name.to_a
    children_of = genres.group_by(&:parent_id)
    (children_of[nil] || []).filter_map do |root|
      next unless children_of.key?(root.id)

      genre_filter_node(root, children_of)
    end
  end

  def genre_filter_node(genre, children_of)
    child_nodes = (children_of[genre.id] || []).filter_map { |child| genre_filter_node(child, children_of) }
    count = genre.events_count + child_nodes.sum { |node| node[:count] }
    return nil if count.zero?

    { name: genre.name, value: genre.name, count: count,
      search: ([genre.name] + child_nodes.map { |node| node[:search] }).join(" "),
      children: child_nodes }
  end

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

      title = Location.canton_name(canton)
      { name: canton, value: canton, type: :canton, title: title,
        count: counts[canton] || locality_nodes.sum { |c| c[:count] },
        search: ([canton, title] + locality_nodes.flat_map { |c| [c[:name]] + c[:children].map { |v| v[:name] } }).join(" "),
        children: locality_nodes }
    end
  end
end
