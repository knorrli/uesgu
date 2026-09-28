class ExcludedGenres
  def self.for(user, picked: [])
    return new({}) unless user

    roots = Genre.where(id: user.genre_exclusions.select(:genre_id)).canonical_ids
    picked_ids = Genre.where(fingerprint: Array(picked).map { |name| Genre.fingerprint_for(name) }).canonical_ids
    new(roots.index_with { |root| Genre.subtree_ids(root) }).lifted_by(picked_ids)
  end

  def initialize(subtrees)
    @subtrees = subtrees
  end

  def roots = subtrees.keys

  def any? = roots.any?

  def lifted_by(genre_ids)
    self.class.new(subtrees.reject { |_root, subtree| subtree.intersect?(genre_ids) })
  end

  def names
    @names ||= Genre.subtree_names(roots)
  end

  def apply(events)
    any? ? events.where.not(id: tagged_event_ids) : events
  end

  def excluded_from(events)
    any? ? events.where(id: tagged_event_ids) : events.none
  end

  def genre_filter_counts
    counts = Genre.filter_counts(apply(Event.listed))
    subtrees.values.flatten.uniq.group_by { |id| lifted_by([id]).roots }.each do |remaining, ids|
      lifted = self.class.new(subtrees.slice(*remaining))
      counts.merge!(Genre.filter_counts(lifted.apply(Event.listed)).slice(*ids))
    end
    counts
  end

  def location_filter_counts
    Event.listed_tag_counts("locations", apply(Event.listed))
  end

  private

  attr_reader :subtrees

  def tagged_event_ids
    ActsAsTaggableOn::Tagging.joins(:tag)
                             .where(context: "genres", taggable_type: Event.name, tags: { name: names })
                             .select(:taggable_id)
  end
end
