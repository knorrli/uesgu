class Genre < ApplicationRecord
  # A genre is a raw, scraped descriptor (e.g. "indie-rock", "techno"). It maps
  # to zero or more curated Styles; an event's styles are derived from the styles
  # of its genres (see Event#recompute_styles!). Genres live alongside the AATO
  # genre tags on events and are matched to them by *fingerprint* (see
  # fingerprint_for) so spelling variants collapse to one row.
  has_and_belongs_to_many :styles

  # An alias points at the canonical genre it should be treated as (e.g.
  # "Elektronik" → "Electronic"): semantic merges the fingerprint can't catch.
  belongs_to :canonical, class_name: 'Genre', optional: true
  has_many :aliases, class_name: 'Genre', foreign_key: :canonical_id,
                     inverse_of: :canonical, dependent: :nullify

  # The genre tree: a genre sits under one parent (e.g. Crustpunk → Punk → Rock),
  # forming the curated taxonomy that supersedes the flat Style layer. A tree, not
  # a DAG — one primary parent only. Filtering by a genre matches it OR any
  # descendant (see subtree_ids). A root genre (no parent) is a top-level browse
  # bucket. Orphan, don't cascade, on delete — losing a parent shouldn't delete
  # the subtree. See docs/taxonomy-and-saved-filters-redesign.md.
  belongs_to :parent, class_name: 'Genre', optional: true
  has_many :children, class_name: 'Genre', foreign_key: :parent_id,
                      inverse_of: :parent, dependent: :nullify

  # Unassigned = the assignment queue: in active use, mapped to no style, and
  # carrying no disposition (including not an alias). Ordered most-used first so
  # the highest-impact genres surface.
  scope :in_use, -> { where('events_count > 0') }
  scope :unassigned, lambda {
    in_use.left_joins(:styles)
          .where(styles: { id: nil }, ignored_at: nil, hidden_at: nil, blocked_at: nil, canonical_id: nil)
          .distinct
  }
  scope :assigned, -> { joins(:styles).distinct }
  # Tree curation queue: in active use, sitting under no parent and carrying no
  # disposition or alias — the genres still waiting to be filed into the tree.
  # The parent-based successor to `unassigned` (which keys off Style); both
  # coexist until Style is removed (Phase 2). Ordered most-used first by by_usage.
  scope :unplaced, lambda {
    in_use.where(parent_id: nil, ignored_at: nil, hidden_at: nil, blocked_at: nil, canonical_id: nil)
  }
  scope :placed, -> { where.not(parent_id: nil) }
  scope :roots, -> { where(parent_id: nil) }
  scope :ignored, -> { where.not(ignored_at: nil) }
  scope :hidden, -> { where.not(hidden_at: nil) }
  scope :blocked, -> { where.not(blocked_at: nil) }
  scope :aliased, -> { where.not(canonical_id: nil) }
  # The catalogue: genres actually in use OR parked (given a disposition or merged
  # into a canonical). Excludes the dormant taxonomy entries (count 0, pre-mapped
  # by the seed) that have never appeared on an event — they'd swamp the curation
  # views. Blocked/aliased genres tag 0 events yet stay listed via their mark so
  # Restore stays reachable. Genres outside this set remain findable by name
  # search (see GenresController#index), so nothing is truly hidden.
  scope :listable, lambda {
    where('events_count > 0 OR ignored_at IS NOT NULL OR hidden_at IS NOT NULL ' \
          'OR blocked_at IS NOT NULL OR canonical_id IS NOT NULL')
  }
  scope :by_usage, -> { order(events_count: :desc, name: :asc) }
  scope :by_name, -> { order(name: :asc) }

  # Folded accented Latin letters used by both the SQL `fingerprint` generated
  # column (see AddFingerprintToGenres) and fingerprint_for below. Keep in sync.
  FINGERPRINT_ACCENTS_FROM = 'äöüàâéèêëïîôûç'.freeze
  FINGERPRINT_ACCENTS_TO   = 'aouaaeeeeiiouc'.freeze

  # Curated display spellings, keyed by fingerprint. Reuses the alias-map
  # canonicals so collapsed variants surface with a nice name (the lowercase
  # taxonomy seed and raw scrapes both store a pretty `name`; `fingerprint` stays
  # the matching key). Anything not listed falls back to titleize_genre.
  DISPLAY_OVERRIDES = {
    'hiphop' => 'Hip Hop', 'postpunk' => 'Post-Punk', 'blackmetal' => 'Black Metal',
    'indiepop' => 'Indie Pop', 'randb' => 'R&B', 'dreampop' => 'Dream Pop',
    'indiefolk' => 'Indie Folk', 'postrock' => 'Post-Rock', 'progrock' => 'Prog Rock',
    'garagerock' => 'Garage Rock', 'punkrock' => 'Punk Rock', 'bluesrock' => 'Blues Rock',
    'globalperreo' => 'Global Perreo', 'hardrock' => 'Hard Rock', 'indiepunk' => 'Indie Punk',
    'italodisco' => 'Italo Disco', 'noiserock' => 'Noise Rock', 'numetal' => 'Nu-Metal',
    'synthpop' => 'Synth Pop', 'drumandbass' => 'Drum & Bass', 'nyhc' => 'NYHC',
    'psychrock' => 'Psych Rock'
  }.freeze

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

  def aliased?
    canonical_id.present?
  end

  def placed?
    parent_id.present?
  end

  # The id of this genre and every genre transitively beneath it in the tree —
  # the set a "filter by this genre" expands to (match the genre OR any
  # descendant). A single recursive query, freshly evaluated so it never goes
  # stale after a re-parent (the doc's "cached descendant_ids OR recursive CTE"
  # — CTE chosen for correctness; wrap in a cache later if the read volume grows).
  # UNION (not UNION ALL) so a stray parent cycle terminates instead of looping.
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

  # This genre's descendants (excluding itself). Memoised per instance.
  def descendant_ids
    @descendant_ids ||= self.class.subtree_ids([id]) - [id]
  end

  # The normalized matching key. MUST reproduce the SQL `fingerprint` generated
  # column exactly (AddFingerprintToGenres) — verified by test. Used at ingest on
  # raw scraped strings that have no row to read the stored column off.
  def self.fingerprint_for(str)
    str.to_s.downcase
       .gsub('&', 'and').gsub("'n'", 'and')
       .tr(FINGERPRINT_ACCENTS_FROM, FINGERPRINT_ACCENTS_TO)
       .gsub(/[^a-z0-9]/, '')
  end

  # The display spelling for a (possibly messy) scraped/seeded name: a curated
  # override if any, else a title-caser that — unlike Rails #titleize — preserves
  # `-`, `/`, and `&` separators (so "post-punk" → "Post-Punk", not "Post Punk").
  def self.display_name_for(str)
    DISPLAY_OVERRIDES[fingerprint_for(str)] || titleize_genre(str)
  end

  def self.titleize_genre(str)
    str.to_s.strip.split(/([ \-\/&])/).map { |part| part.match?(/[a-z]/i) ? part.capitalize : part }.join
  end

  # The style names mapped to the given genre names, matched by fingerprint (the
  # single source of truth used by both Event#recompute_styles! and the scrape
  # path). Robust to spelling variants without any per-variant upkeep.
  def self.styles_for(names)
    fingerprints = Array(names).map { |name| fingerprint_for(name) }.uniq.reject(&:blank?)
    return [] if fingerprints.empty?

    Style.joins(:genres).where(genres: { fingerprint: fingerprints }).distinct.pluck(:name)
  end

  # Replace each scraped name with the canonical *display* name of the Genre it
  # resolves to (by fingerprint): the collapsed spelling for known genres, the
  # canonical for semantic aliases, or a titleized form for brand-new ones. This
  # is what dedupes the publicly-shown genre tag — see Event#genre_list=.
  def self.canonicalize_names(names)
    names = Array(names).map(&:to_s)
    return names if names.empty?

    fingerprints = names.map { |name| fingerprint_for(name) }
    rows = where(fingerprint: fingerprints.uniq).includes(:canonical).index_by(&:fingerprint)
    names.each_with_index.map do |name, i|
      genre = rows[fingerprints[i]]
      if genre.nil? then display_name_for(name)
      elsif genre.canonical then genre.canonical.name
      else genre.name
      end
    end
  end

  # Set this genre's styles (clearing any disposition/alias) and re-derive the
  # styles (and visibility) of every event carrying it.
  def assign_styles!(ids)
    # Accepts the combobox's comma-joined string ("3,7") or a single id.
    ids = Array(ids).join(',').split(',').map(&:strip).reject(&:blank?)
    transaction do
      self.style_ids = ids
      update!(ignored_at: nil, hidden_at: nil, blocked_at: nil, canonical_id: nil)
    end
    recompute_events!
  end

  # File this genre into the tree under `parent` (a Genre or its id; nil detaches
  # it back to a root). The parent-based successor to assign_styles! — a placed
  # genre carries no disposition or alias, so clear those. Rejects parenting a
  # genre under itself or its own descendant (which would form a cycle). Re-derives
  # events so a previously-hidden genre re-surfaces once it's placed.
  def set_parent!(parent)
    new_parent_id = parent.is_a?(Genre) ? parent.id : parent.presence&.to_i
    if new_parent_id && self.class.subtree_ids([id]).include?(new_parent_id)
      raise ArgumentError, 'a genre cannot be parented under itself or its own descendant'
    end

    transaction do
      update!(parent_id: new_parent_id, ignored_at: nil, hidden_at: nil, blocked_at: nil, canonical_id: nil)
    end
    recompute_events!
  end

  # "Ignore" it for mapping: a real, publicly-shown genre we deliberately leave
  # unmapped. Clear styles, set ignored_at, re-derive events.
  def ignore!
    transaction do
      styles.clear
      update!(ignored_at: Time.current, hidden_at: nil, blocked_at: nil, canonical_id: nil, parent_id: nil)
    end
    recompute_events!
  end

  # "Hide": mark as non-music. Clear styles, set hidden_at. Events carrying only
  # this (and no music style) drop out of public listings — see Event#recompute_styles!.
  def hide!
    transaction do
      styles.clear
      update!(hidden_at: Time.current, ignored_at: nil, blocked_at: nil, canonical_id: nil, parent_id: nil)
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
      update!(blocked_at: Time.current, ignored_at: nil, hidden_at: nil, canonical_id: nil, parent_id: nil)
    end
    # Snapshot ids first: recompute_styles! drops this genre's tagging from each
    # event, shrinking the tagged_with set find_each would page over — which would
    # skip events and leave the blocked tag attached (cf. merge_into!).
    affected = Event.tagged_with(name, on: :genres).pluck(:id)
    Event.where(id: affected).find_each do |event|
      event.genre_list.remove(name)
      event.recompute_styles! # persists the dropped tagging + re-derives styles
    end
    update_columns(events_count: 0)
  end

  # Merge this genre into a canonical one (a semantic alias the fingerprint can't
  # catch, e.g. "Elektronik" → "Electronic"). Operates on AATO taggings directly
  # (never via genre_list, which would re-parse and trip the unique tag index):
  # repoints this genre's event taggings onto the canonical tag, dropping
  # duplicates where an event already carries the canonical. Idempotent — re-runs
  # converge to a no-op. Future scrapes auto-resolve via Genre.canonicalize_names.
  def merge_into!(canonical)
    raise ArgumentError, 'a genre cannot be merged into itself' if canonical.id == id

    affected = []
    transaction do
      alias_tag = ActsAsTaggableOn::Tag.named(name).first
      if alias_tag
        canonical_tag = ActsAsTaggableOn::Tag.find_or_create_all_with_like_by_name(canonical.name).first
        taggings = ActsAsTaggableOn::Tagging.where(context: 'genres', taggable_type: Event.name, tag_id: alias_tag.id)
        affected = taggings.pluck(:taggable_id)
        # Events already carrying the canonical tag: drop the duplicate alias
        # tagging instead of repointing (which would violate the unique index).
        dup_ids = ActsAsTaggableOn::Tagging
                  .where(context: 'genres', taggable_type: Event.name, tag_id: canonical_tag.id, taggable_id: affected)
                  .pluck(:taggable_id)
        taggings.where(taggable_id: dup_ids).delete_all
        taggings.update_all(tag_id: canonical_tag.id)
      end
      styles.clear
      update!(canonical_id: canonical.id, ignored_at: nil, hidden_at: nil, blocked_at: nil, parent_id: nil)
    end
    Event.where(id: affected).find_each(&:recompute_styles!)
    Genre.reconcile!
  end

  # Back to the queue: clear every mark (disposition or alias) and re-derive
  # events. Like restoring a blocked genre, repointed/stripped taggings don't
  # come back — restore only lifts the mark for future scrapes.
  def restore!
    update!(ignored_at: nil, hidden_at: nil, blocked_at: nil, canonical_id: nil, parent_id: nil)
    recompute_events!
  end

  # Fingerprints of every blocked genre, for blocklist matching at tagging time
  # (see Event#genre_list=) — fingerprint-based so spelling variants are caught.
  def self.blocked_fingerprints
    blocked.pluck(:fingerprint).to_set
  end

  # Ensure a Genre row exists for each given name, matched and de-duplicated by
  # fingerprint (so "Post Punk" resolves to an existing "Post-Punk" rather than
  # spawning a third row). New rows are stored under their display name.
  def self.ensure!(names)
    names = Array(names).map(&:to_s).reject(&:blank?).uniq
    return if names.empty?

    representative = names.index_by { |name| fingerprint_for(name) } # fingerprint => a raw name
    existing = where(fingerprint: representative.keys).pluck(:fingerprint)
    (representative.keys - existing).each do |fingerprint|
      create!(name: display_name_for(representative[fingerprint]))
    rescue ActiveRecord::RecordNotUnique
      next # a concurrent insert or fingerprint race already created it
    end
  end

  # The match-only counterpart to ensure!: the subset of `names` that already
  # resolve to a Genre row by fingerprint, creating NOTHING. Used by
  # consumption-only scrapers (unstable free-text sources — artist blurbs,
  # subtitle prose, country codes) so they may attach only genres already in the
  # curated vocabulary and can never mint new taxonomy from noise.
  def self.existing_only(names)
    names = Array(names).map(&:to_s).reject(&:blank?)
    return [] if names.empty?

    present = where(fingerprint: names.map { |name| fingerprint_for(name) }).pluck(:fingerprint).to_set
    names.select { |name| present.include?(fingerprint_for(name)) }
  end

  # Refresh the cached usage count from the current genre taggings on events,
  # creating rows for any new genres and zeroing those no longer in use. Folds
  # tag-name variants that share a fingerprint into the one Genre, so a stray
  # case/spacing variant never re-splits what fingerprinting merged.
  def self.reconcile!
    counts = ActsAsTaggableOn::Tagging
             .where(context: 'genres', taggable_type: Event.name)
             .joins(:tag).group('tags.name').count

    by_fingerprint = Hash.new(0)
    representative = {}
    counts.each do |name, count|
      fingerprint = fingerprint_for(name)
      by_fingerprint[fingerprint] += count
      representative[fingerprint] ||= name
    end

    ensure!(representative.values)
    rows = where(fingerprint: by_fingerprint.keys.presence || ['']).index_by(&:fingerprint)
    by_fingerprint.each { |fingerprint, count| rows[fingerprint]&.update_columns(events_count: count) }
    # Zero every genre outside the current tag set. The `|| ['']` matters: when the
    # set is empty it's *all* genres, and no fingerprint is '', so NOT IN ('')
    # matches every row — whereas NOT IN (NULL) would be SQL-unknown and zero none.
    where.not(fingerprint: by_fingerprint.keys.presence || ['']).update_all(events_count: 0)
  end

  private

  def recompute_events!
    Event.tagged_with(name, on: :genres).find_each(&:recompute_styles!)
  end
end
