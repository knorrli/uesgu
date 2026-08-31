class Genre < ApplicationRecord
  belongs_to :canonical, class_name: "Genre", optional: true
  has_many :aliases, class_name: "Genre", foreign_key: :canonical_id,
                     inverse_of: :canonical, dependent: :nullify

  belongs_to :parent, class_name: "Genre", optional: true
  has_many :children, class_name: "Genre", foreign_key: :parent_id,
                      inverse_of: :parent, dependent: :nullify

  validates :name, presence: true, on: :rename
  validate :fingerprint_available, on: :rename

  scope :in_use, -> { where("events_count > 0") }
  scope :offerable, -> { in_use.where(ignored_at: nil, hidden_at: nil, blocked_at: nil, canonical_id: nil) }
  scope :unplaced, lambda {
    in_use.where(parent_id: nil, ignored_at: nil, hidden_at: nil, blocked_at: nil, canonical_id: nil)
          .where.not(id: Genre.where.not(parent_id: nil).select(:parent_id))
  }
  scope :placed, -> { where.not(parent_id: nil) }
  scope :roots, -> { where(parent_id: nil) }
  scope :ignored, -> { where.not(ignored_at: nil) }
  scope :hidden, -> { where.not(hidden_at: nil) }
  scope :blocked, -> { where.not(blocked_at: nil) }
  scope :aliased, -> { where.not(canonical_id: nil) }
  scope :listable, lambda {
    where("events_count > 0 OR ignored_at IS NOT NULL OR hidden_at IS NOT NULL " \
          "OR blocked_at IS NOT NULL OR canonical_id IS NOT NULL " \
          "OR EXISTS (SELECT 1 FROM genres aliases WHERE aliases.canonical_id = genres.id)")
  }
  scope :by_usage, -> { order(events_count: :desc, name: :asc) }
  scope :by_name, -> { order(name: :asc) }

  DISPLAY_OVERRIDES = {
    "hiphop" => "Hip Hop", "postpunk" => "Post-Punk", "blackmetal" => "Black Metal",
    "indiepop" => "Indie Pop", "randb" => "R&B", "dreampop" => "Dream Pop",
    "indiefolk" => "Indie Folk", "postrock" => "Post-Rock", "progrock" => "Prog Rock",
    "garagerock" => "Garage Rock", "punkrock" => "Punk Rock", "bluesrock" => "Blues Rock",
    "globalperreo" => "Global Perreo", "hardrock" => "Hard Rock", "indiepunk" => "Indie Punk",
    "italodisco" => "Italo Disco", "noiserock" => "Noise Rock", "numetal" => "Nu-Metal",
    "synthpop" => "Synth Pop", "drumandbass" => "Drum & Bass", "nyhc" => "NYHC",
    "psychrock" => "Psych Rock"
  }.freeze

  def to_s
    name
  end

  def to_combobox_display
    name
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

  def aliased?
    canonical_id.present?
  end

  def placed?
    parent_id.present?
  end

  def self.subtree_ids(root_ids)
    root_ids = Array(root_ids).map(&:to_i).uniq
    return [] if root_ids.empty?

    sql = sanitize_sql_array([<<~SQL.squish, root_ids])
      WITH RECURSIVE subtree(id) AS (
        SELECT id FROM genres WHERE id IN (?)
        UNION
        SELECT g.id FROM genres g JOIN subtree s ON g.parent_id = s.id
      )
      SELECT id FROM subtree
    SQL
    connection.select_values(sql).map(&:to_i)
  end

  def descendant_ids
    @descendant_ids ||= self.class.subtree_ids([id]) - [id]
  end

  def self.descendant_counts
    children = Hash.new { |hash, key| hash[key] = [] }
    pluck(:id, :parent_id).each { |id, parent_id| children[parent_id] << id if parent_id }
    counts = Hash.new(0)
    walk = ->(id) { children.fetch(id, []).sum { |child| 1 + walk.call(child) } }
    children.keys.each { |parent_id| counts[parent_id] = walk.call(parent_id) }
    counts
  end

  def self.ancestor_paths
    rows      = pluck(:id, :parent_id, :name)
    name_of   = rows.to_h { |id, _parent, name| [id, name] }
    parent_of = rows.to_h { |id, parent, _name| [id, parent] }
    paths = {}
    build = lambda do |id|
      paths[id] ||= (parent = parent_of[id]) ? build.call(parent) + [name_of[parent]] : []
    end
    parent_of.each_key { |id| build.call(id) }
    paths
  end

  def self.fingerprint_for(str)
    Fingerprint.for(str)
  end

  def self.display_name_for(str)
    DISPLAY_OVERRIDES[fingerprint_for(str)] || titleize_genre(str)
  end

  GENRE_EDGE_NOISE = /\A[^[:alnum:]]+|[^[:alnum:]]+\z/

  def self.titleize_genre(str)
    str.to_s.strip.gsub(GENRE_EDGE_NOISE, "")
       .split(/([ \-\/&])/).map { |part| part.match?(/[a-z]/i) ? part.capitalize : part }.join
  end

  def self.filter_names_for(picked_names)
    picked_names = Array(picked_names).map(&:to_s).reject(&:blank?)
    return [] if picked_names.empty?

    root_ids = where(fingerprint: picked_names.map { |name| fingerprint_for(name) }).ids
    subtree = subtree_ids(root_ids)
    (where(id: subtree).pluck(:name) + where(canonical_id: subtree).pluck(:name)).uniq
  end

  PROSE_MINING_STOPWORDS = %w[
    house pop soul folk country garage industrial drum band world wave experimental
  ].freeze

  def self.prose_mining_index
    stop = PROSE_MINING_STOPWORDS.to_set { |word| fingerprint_for(word) }
    where(blocked_at: nil).pluck(:fingerprint, :name)
                          .reject { |fingerprint, _| fingerprint.blank? || stop.include?(fingerprint) }
                          .to_h
  end

  def self.names_in_prose(text, index)
    return [] if text.blank? || index.empty?

    words = text.to_s.split
    found = []
    i = 0
    while i < words.size
      name = nil
      span = 1
      3.downto(1) do |n|
        next if i + n > words.size

        if (hit = index[fingerprint_for(words[i, n].join(" "))])
          name = hit
          span = n
          break
        end
      end
      found << name if name
      i += span
    end
    found.uniq
  end

  def self.canonicalize_names(names)
    names = Array(names).map(&:to_s)
    return names if names.empty?

    fingerprints = names.map { |name| fingerprint_for(name) }
    rows = where(fingerprint: fingerprints.uniq).index_by(&:fingerprint)
    names.each_with_index.map do |name, i|
      genre = rows[fingerprints[i]]
      genre ? genre.name : display_name_for(name)
    end
  end

  def set_parent!(parent)
    new_parent_id = parent.is_a?(Genre) ? parent.id : parent.presence&.to_i
    if new_parent_id && self.class.subtree_ids([id]).include?(new_parent_id)
      raise ArgumentError, "a genre cannot be parented under itself or its own descendant"
    end

    transaction do
      update!(parent_id: new_parent_id, ignored_at: nil, hidden_at: nil, blocked_at: nil, canonical_id: nil)
    end
    recompute_events!
  end

  def ignore!
    transaction do
      update!(ignored_at: Time.current, hidden_at: nil, blocked_at: nil, canonical_id: nil, parent_id: nil)
    end
    recompute_events!
  end

  def hide!
    transaction do
      update!(hidden_at: Time.current, ignored_at: nil, blocked_at: nil, canonical_id: nil, parent_id: nil)
    end
    recompute_events!
  end

  def block!
    transaction do
      update!(blocked_at: Time.current, ignored_at: nil, hidden_at: nil, canonical_id: nil, parent_id: nil)
    end
    affected = Event.tagged_with(name, on: :genres).pluck(:id)
    Event.where(id: affected).find_each do |event|
      event.genre_list.remove(name)
      event.recompute_visibility!
    end
    update_columns(events_count: 0)
  end

  def merge_into!(canonical)
    raise ArgumentError, "a genre cannot be merged into itself" if canonical.id == id

    update!(canonical_id: canonical.id, ignored_at: nil, hidden_at: nil, blocked_at: nil, parent_id: nil)
    Genre.reconcile!
  end

  def rename!(new_name)
    previous = fingerprint
    self.name = new_name.to_s.strip
    unless valid?(:rename)
      restore_attributes
      return false
    end

    transaction do
      save!
      retag_events(previous)
      rewrite_saved_filters(previous)
    end
    true
  end

  def restore!
    update!(ignored_at: nil, hidden_at: nil, blocked_at: nil, canonical_id: nil, parent_id: nil)
    recompute_events!
  end

  def self.blocked_fingerprints
    blocked.pluck(:fingerprint).to_set
  end

  def self.ensure!(names)
    names = Array(names).map(&:to_s).reject(&:blank?).uniq
    return if names.empty?

    representative = names.index_by { |name| fingerprint_for(name) }
    existing = where(fingerprint: representative.keys).pluck(:fingerprint)
    (representative.keys - existing).each do |fingerprint|
      display = display_name_for(representative[fingerprint])
      next if display.blank?
      create!(name: display)
    rescue ActiveRecord::RecordNotUnique
      next
    end
  end

  def self.reconcile!
    counts = ActsAsTaggableOn::Tagging
             .where(context: "genres", taggable_type: Event.name)
             .joins(:tag).group("tags.name").count

    by_fingerprint = Hash.new(0)
    representative = {}
    counts.each do |name, count|
      fingerprint = fingerprint_for(name)
      by_fingerprint[fingerprint] += count
      representative[fingerprint] ||= name
    end

    ensure!(representative.values)
    rows = where(fingerprint: by_fingerprint.keys.presence || [""]).index_by(&:fingerprint)
    by_fingerprint.each { |fingerprint, count| rows[fingerprint]&.update_columns(events_count: count) }
    # Zero every genre outside the current tag set. The `|| ['']` matters: when the
    # set is empty it's *all* genres, and no fingerprint is '', so NOT IN ('')
    # matches every row — whereas NOT IN (NULL) would be SQL-unknown and zero none.
    where.not(fingerprint: by_fingerprint.keys.presence || [""]).update_all(events_count: 0)
  end

  private

  def fingerprint_available
    return if name.blank?

    duplicates = Genre.where(fingerprint: Genre.fingerprint_for(name)).where.not(id: id)
    errors.add(:name, :taken) if duplicates.exists?
  end

  def variant_tag_names(of_fingerprint)
    ActsAsTaggableOn::Tag.joins(:taggings)
                         .where(taggings: { context: "genres", taggable_type: Event.name })
                         .distinct.pluck(:name)
                         .select { |tag| Genre.fingerprint_for(tag) == of_fingerprint }
  end

  def retag_events(of_fingerprint)
    variant_tag_names(of_fingerprint).each do |variant|
      next if variant == name

      Event.where(id: Event.tagged_with(variant, on: :genres).pluck(:id)).find_each do |event|
        event.genre_list.remove(variant)
        event.genre_list.add(name)
        event.save!
      end
    end
  end

  def rewrite_saved_filters(of_fingerprint)
    SavedFilter.find_each do |saved|
      rewritten = saved.genres.map { |picked| Genre.fingerprint_for(picked) == of_fingerprint ? name : picked }.uniq
      next if rewritten == saved.genres

      saved.filter = saved.filter.merge("genres" => rewritten)
      redundant?(saved) ? saved.destroy! : saved.save!
    end
  end

  def redundant?(saved)
    saved.user.saved_filters.where.not(id: saved.id).any? { |other| other.fingerprint == saved.fingerprint }
  end

  def recompute_events!
    Event.tagged_with(name, on: :genres).find_each(&:recompute_visibility!)
  end
end
