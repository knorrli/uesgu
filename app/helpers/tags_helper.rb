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
    when 'region'
      'ti-world'
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
end
