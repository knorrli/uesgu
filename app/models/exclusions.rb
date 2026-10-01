class Exclusions
  def self.for(user, genres: [], locations: [])
    return new({}, []) unless user

    roots = Genre.where(id: user.genre_exclusions.select(:genre_id)).canonical_ids
    picked_ids = Genre.where(fingerprint: Array(genres).map { |name| Genre.fingerprint_for(name) }).canonical_ids
    new(roots.index_with { |root| Genre.subtree_ids(root) }, user.location_exclusions.pluck(:name))
      .lifted_by(picked_ids)
      .without_locations(Array(locations))
  end

  def initialize(subtrees, locations)
    @subtrees = subtrees
    @locations = locations
  end

  def genre_roots = subtrees.keys

  def any? = genre_roots.any? || locations.any?

  def lifted_by(genre_ids)
    self.class.new(subtrees.reject { |_root, subtree| subtree.intersect?(genre_ids) }, locations)
  end

  def without_locations(names)
    self.class.new(subtrees, locations - names)
  end

  def apply(events)
    any? ? events.where.not(id: tagged_event_ids) : events
  end

  def excluded_from(events)
    any? ? events.where(id: tagged_event_ids) : events.none
  end

  def genre_filter_counts
    counts = Genre.filter_counts(apply(Event.listed))
    subtrees.values.flatten.uniq.group_by { |id| lifted_by([id]).genre_roots }.each do |remaining, ids|
      lifted = self.class.new(subtrees.slice(*remaining), locations)
      counts.merge!(Genre.filter_counts(lifted.apply(Event.listed)).slice(*ids))
    end
    counts
  end

  def location_filter_counts
    counts = Event.listed_tag_counts("locations", apply(Event.listed))
    locations.each do |name|
      counts.merge!(Event.listed_tag_counts("locations", without_locations([name]).apply(Event.listed)).slice(name))
    end
    counts
  end

  private

  attr_reader :subtrees, :locations

  def genre_names
    @genre_names ||= Genre.subtree_names(genre_roots)
  end

  def tagged_event_ids
    taggings = ActsAsTaggableOn::Tagging.joins(:tag).where(taggable_type: Event.name)
    taggings.where(context: "genres", tags: { name: genre_names })
            .or(taggings.where(context: "locations", tags: { name: locations }))
            .select(:taggable_id)
  end
end
