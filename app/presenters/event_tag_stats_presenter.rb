class EventTagStatsPresenter
  def location_tags
    ActsAsTaggableOn::Tag
      .includes(:taggings)
      .where(taggings: { context: 'locations', taggable_type: Event.name })
  end

  def style_tags
    ActsAsTaggableOn::Tag
      .includes(:taggings)
      .where(taggings: { context: 'styles', taggable_type: Event.name })
  end

  # Genres are now first-class; "in use" means present on at least one event.
  def genre_tags
    Genre.in_use
  end

  def assigned_genre_tags
    Genre.in_use.assigned
  end

  def unassigned_genre_tags
    Genre.unassigned
  end

  def ignored_genre_tags
    Genre.in_use.ignored
  end

  def hidden_genre_tags
    Genre.in_use.hidden
  end

  def blocked_genre_tags
    Genre.in_use.blocked
  end
end
