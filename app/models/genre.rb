class Genre < ApplicationRecord
  # A genre is a raw, scraped descriptor (e.g. "indie-rock", "techno"). It maps
  # to zero or more curated Styles; an event's styles are derived from the
  # styles of its genres (see Event#recompute_styles!). Genres live alongside
  # the AATO genre tags on events and are matched to them by name.
  has_and_belongs_to_many :styles

  # Unassigned = the assignment queue: in active use, mapped to no style, and
  # neither dismissed nor excluded. Ordered most-used first so the highest-impact
  # genres surface.
  scope :in_use, -> { where('events_count > 0') }
  scope :unassigned, -> { in_use.left_joins(:styles).where(styles: { id: nil }, dismissed_at: nil, excluded_at: nil).distinct }
  scope :assigned, -> { joins(:styles).distinct }
  scope :dismissed, -> { where.not(dismissed_at: nil) }
  scope :excluded, -> { where.not(excluded_at: nil) }
  scope :by_usage, -> { order(events_count: :desc, name: :asc) }

  def to_s
    name
  end

  def to_combobox_display
    name
  end

  def assigned?
    styles.exists?
  end

  def dismissed?
    dismissed_at.present?
  end

  def excluded?
    excluded_at.present?
  end

  # Set this genre's styles (clearing any won't-fix / not-music mark) and
  # re-derive the styles (and visibility) of every event carrying it.
  def assign_styles!(ids)
    # Accepts the combobox's comma-joined string ("3,7") or a single id.
    ids = Array(ids).join(',').split(',').map(&:strip).reject(&:blank?)
    transaction do
      self.style_ids = ids
      update!(dismissed_at: nil, excluded_at: nil)
    end
    recompute_events!
  end

  # Mark intentionally unmapped (still a real, visible genre): clear styles, set
  # dismissed_at, re-derive events.
  def dismiss!
    transaction do
      styles.clear
      update!(dismissed_at: Time.current, excluded_at: nil)
    end
    recompute_events!
  end

  # Mark as non-music: clear styles, set excluded_at. Events carrying only this
  # (and no music style) drop out of public listings — see Event#recompute_styles!.
  def exclude!
    transaction do
      styles.clear
      update!(excluded_at: Time.current, dismissed_at: nil)
    end
    recompute_events!
  end

  # Back to the queue: clear both marks and re-derive events (un-hiding any it
  # was hiding).
  def restore!
    update!(dismissed_at: nil, excluded_at: nil)
    recompute_events!
  end

  # Ensure a Genre row exists for each given name (e.g. freshly scraped genres).
  # Matches case-insensitively to line up with the unique lower(name) index, so
  # a case variant of an existing genre never attempts a duplicate insert.
  def self.ensure!(names)
    names = Array(names).map(&:to_s).uniq
    existing = where('lower(name) IN (?)', names.map(&:downcase)).pluck(Arel.sql('lower(name)'))
    names.reject { |name| existing.include?(name.downcase) }
         .each { |name| create_or_find_by!(name: name) }
  end

  # Refresh the cached usage count from the current genre taggings on events,
  # creating rows for any new genres and zeroing those no longer in use.
  # Matches case-insensitively so a taxonomy-imported genre and a scraped tag
  # that differ only in case map to the same row.
  def self.reconcile!
    counts = ActsAsTaggableOn::Tagging
      .where(context: 'genres', taggable_type: Event.name)
      .joins(:tag)
      .group('tags.name')
      .count

    ensure!(counts.keys)
    by_lower = where('lower(name) IN (?)', counts.keys.map(&:downcase).presence || [nil])
               .index_by { |genre| genre.name.downcase }
    counts.each { |name, count| by_lower[name.downcase]&.update_columns(events_count: count) }

    where('lower(name) NOT IN (?)', counts.keys.map(&:downcase).presence || [nil])
      .update_all(events_count: 0)
  end

  private

  def recompute_events!
    Event.tagged_with(name, on: :genres).find_each(&:recompute_styles!)
  end
end
