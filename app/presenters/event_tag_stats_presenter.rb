class EventTagStatsPresenter
  def location_tags
    ActsAsTaggableOn::Tag
      .includes(:taggings)
      .where(taggings: { context: 'locations', taggable_type: Event.name })
  end

  # Genres are now first-class; "in use" means present on at least one event.
  def genre_tags
    Genre.in_use
  end

  # Filed into the tree (placed under a parent) vs. still waiting in the queue.
  def placed_genre_tags
    Genre.in_use.placed
  end

  def unplaced_genre_tags
    Genre.unplaced
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
