class Genre < ApplicationRecord
  # A genre is a raw, scraped descriptor (e.g. "indie-rock", "techno"). It maps
  # to zero or more curated Styles; an event's styles are derived from the
  # styles of its genres (see Event#recompute_styles!). Genres live alongside
  # the AATO genre tags on events and are matched to them by name.
  has_and_belongs_to_many :styles

  # Unassigned = the assignment queue: in active use, mapped to no style, and
  # carrying no disposition. Ordered most-used first so the highest-impact genres
  # surface.
  scope :in_use, -> { where('events_count > 0') }
  scope :unassigned, -> { in_use.left_joins(:styles).where(styles: { id: nil }, ignored_at: nil, hidden_at: nil, blocked_at: nil).distinct }
  scope :assigned, -> { joins(:styles).distinct }
  scope :ignored, -> { where.not(ignored_at: nil) }
  scope :hidden, -> { where.not(hidden_at: nil) }
  scope :blocked, -> { where.not(blocked_at: nil) }
  # The admin index's universe: genres still in use OR ones we've acted on. A
  # blocked genre tags 0 events (its taggings were stripped) yet must stay listed
  # so it can be reviewed/restored — in_use alone would hide it. Same safety net
  # for an ignored/hidden genre a venue has since stopped using.
  scope :listable, -> { where('events_count > 0 OR ignored_at IS NOT NULL OR hidden_at IS NOT NULL OR blocked_at IS NOT NULL') }
  scope :by_usage, -> { order(events_count: :desc, name: :asc) }
  scope :by_name, -> { order(name: :asc) }

  def to_s
    name
  end

  def to_combobox_display
    name
  end

  def assigned?
    styles.exists?
  end

  def ignored?
    ignored_at.present?
  end

  def hidden?
    hidden_at.present?
  end

  def blocked?
    blocked_at.present?
  end

  # Set this genre's styles (clearing any disposition mark) and re-derive the
  # styles (and visibility) of every event carrying it.
  def assign_styles!(ids)
    # Accepts the combobox's comma-joined string ("3,7") or a single id.
    ids = Array(ids).join(',').split(',').map(&:strip).reject(&:blank?)
    transaction do
      self.style_ids = ids
      update!(ignored_at: nil, hidden_at: nil, blocked_at: nil)
    end
    recompute_events!
  end

  # "Ignore" it for mapping: a real, publicly-shown genre we deliberately leave
  # unmapped. Clear styles, set ignored_at, re-derive events.
  def ignore!
    transaction do
      styles.clear
      update!(ignored_at: Time.current, hidden_at: nil, blocked_at: nil)
    end
    recompute_events!
  end

  # "Hide": mark as non-music. Clear styles, set hidden_at. Events carrying only
  # this (and no music style) drop out of public listings — see Event#recompute_styles!.
  def hide!
    transaction do
      styles.clear
      update!(hidden_at: Time.current, ignored_at: nil, blocked_at: nil)
    end
    recompute_events!
  end

  # "Block" scraper noise (never a real genre): clear styles, set blocked_at, and
  # strip this genre's taggings off every event that carries it. The event itself
  # stays untouched and visible — only the junk tag goes. Event#genre_list= then
  # keeps it out on every future scrape, since scrapers re-tag by name.
  def block!
    transaction do
      styles.clear
      update!(blocked_at: Time.current, ignored_at: nil, hidden_at: nil)
    end
    Event.tagged_with(name, on: :genres).find_each do |event|
      event.genre_list.remove(name)
      event.recompute_styles! # persists the dropped tagging + re-derives styles
    end
    update_columns(events_count: 0)
  end

  # Back to the queue: clear every mark and re-derive events (un-hiding any it
  # was hiding). For a previously-blocked genre the stripped taggings only return
  # on the next scrape — restore just lifts the blocklist.
  def restore!
    update!(ignored_at: nil, hidden_at: nil, blocked_at: nil)
    recompute_events!
  end

  # Lowercased set of every blocked genre name, for case-insensitive blocklist
  # matching at tagging time (see Event#genre_list=).
  def self.blocked_names
    blocked.pluck(:name).map(&:downcase).to_set
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
