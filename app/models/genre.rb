class Genre < ApplicationRecord
  # A genre is a raw, scraped descriptor (e.g. "indie-rock", "techno"), filed into
  # a curated tree (see parent below). Genres live alongside the AATO genre tags on
  # events and are matched to them by *fingerprint* (see fingerprint_for) so
  # spelling variants collapse to one row.

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

  scope :in_use, -> { where('events_count > 0') }
  # Tree curation queue: in active use, sitting under no parent, carrying no
  # disposition or alias, AND not itself a parent of other genres — the genres
  # still waiting to be filed into the tree. Excluding parents is what separates
  # an unfiled leaf from a deliberate top-level root (a root has children but no
  # parent, so it would otherwise look unplaced). Ordered most-used first by by_usage.
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
  # The catalogue: genres actually in use OR parked (given a disposition, merged
  # into a canonical, or serving as a canonical for >=1 alias). Excludes the dormant
  # taxonomy entries (count 0, pre-mapped by the seed) that have never appeared on an
  # event — they'd swamp the curation views. Blocked genres tag 0 events yet stay
  # listed via their mark so Restore stays reachable (an aliased genre keeps its own
  # taggings — a query-time link, not a rewrite — so it stays listed via events_count
  # too). A canonical hub can itself sit at count 0 (the live event carries the
  # alias's raw token, not the canonical's) — the EXISTS clause keeps it listed so it
  # doesn't vanish from the catalogue right after a merge. Genres outside this set
  # remain findable by name search (see GenresController#index), so nothing is hidden.
  scope :listable, lambda {
    where('events_count > 0 OR ignored_at IS NOT NULL OR hidden_at IS NOT NULL ' \
          'OR blocked_at IS NOT NULL OR canonical_id IS NOT NULL ' \
          'OR EXISTS (SELECT 1 FROM genres aliases WHERE aliases.canonical_id = genres.id)')
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

  # Descendant count for every genre that has any, in one pass over the adjacency
  # list: a single `pluck(:id, :parent_id)` plus an in-memory tree walk — no
  # per-row query. Powers the "set parent" picker, where candidates with the most
  # sub-genres (the umbrella genres you usually file into) sort first and show the
  # count. Cheap: one lightweight query over the whole (few-hundred-row) table.
  def self.descendant_counts
    children = Hash.new { |hash, key| hash[key] = [] }
    pluck(:id, :parent_id).each { |id, parent_id| children[parent_id] << id if parent_id }
    counts = Hash.new(0)
    walk = ->(id) { children.fetch(id, []).sum { |child| 1 + walk.call(child) } }
    children.keys.each { |parent_id| counts[parent_id] = walk.call(parent_id) }
    counts
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

  # The genre names a picked-genre filter should match: every name in the picked
  # genres' subtrees, PLUS the raw names of any alias that resolves into those
  # subtrees. An event tagged with the raw token "Elektronik" matches a filter for
  # "Electronic" because Elektronik#canonical is Electronic, which sits in the
  # subtree — without the event's stored tag ever being rewritten. Defined once so
  # the filter query (Filter#expanded_genre_names) and the row highlighter
  # (EventsHelper#genre_subtree_names) can't drift apart.
  def self.filter_names_for(picked_names)
    picked_names = Array(picked_names).map(&:to_s).reject(&:blank?)
    return [] if picked_names.empty?

    root_ids = where(fingerprint: picked_names.map { |name| fingerprint_for(name) }).ids
    subtree = subtree_ids(root_ids)
    (where(id: subtree).pluck(:name) + where(canonical_id: subtree).pluck(:name)).uniq
  end

  # Genre names that are also ordinary words — too ambiguous to mine out of free
  # prose, where "the house was packed" / "from every country" / "good for the
  # soul" would false-match. Prose mining (names_in_prose) skips these; they still
  # tag normally from a venue's own curated genre field, where the context is
  # unambiguous. Compared by fingerprint, so spelling variants are caught too.
  # Tunable — widen it if a homograph keeps surfacing junk taggings.
  PROSE_MINING_STOPWORDS = %w[
    house pop soul folk country garage industrial drum band world wave experimental
  ].freeze

  # The vocabulary prose mining matches against: fingerprint => stored display
  # name for every known genre EXCEPT blocked noise (never a real genre) and the
  # everyday-word stoplist above. Built from the same Genre name-space the filter
  # matcher draws on, so a mined token lights up genre filters exactly like a
  # hand-tagged one — including alias raw names (e.g. "Elektronik"), which keep
  # their own fingerprint and resolve to their canonical at query time. The caller
  # builds this ONCE per scrape run (it's a full-table read).
  def self.prose_mining_index
    stop = PROSE_MINING_STOPWORDS.to_set { |word| fingerprint_for(word) }
    where(blocked_at: nil).pluck(:fingerprint, :name)
                          .reject { |fingerprint, _| fingerprint.blank? || stop.include?(fingerprint) }
                          .to_h
  end

  # The known genre names that appear, on word boundaries, in a free-text blob —
  # MATCH-ONLY mining over `index` (fingerprint => name, from prose_mining_index):
  # it attaches existing taxonomy, minting NOTHING new (unlike a scraper's
  # event_genres). Tokenises on whitespace and tests 1..3-word windows by
  # fingerprint, so spelling variants fold the way the genre filter matches
  # ("post punk" → "Post-Punk", "drum and bass" → "Drum & Bass") with no sub-word
  # hits ("Jazzgeschichte" never matches "jazz"). Greedy + non-overlapping:
  # "indie rock" yields the single "Indie Rock", not also "Indie" + "Rock".
  #
  # Known limitation: negation/comparison in prose still matches ("not your
  # typical techno" attaches Techno). Known-vocab-only bounds the blast radius, and
  # a wrong tag is a normal tagging an admin can dismiss/block — but it is NOT
  # zero, so this stays an ingest-only dataset-quality aid, surfaced nowhere new.
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

        if (hit = index[fingerprint_for(words[i, n].join(' '))])
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

  # Replace each scraped name with its canonical *display* spelling, matched by
  # fingerprint: the collapsed spelling for a known genre, or a titleized form for
  # a brand-new one. Cosmetic normalization ONLY (e.g. "post punk" → "Post-Punk").
  # It deliberately does NOT substitute a semantic alias's canonical — an event
  # keeps its raw token ("Elektronik"); the filter resolves the alias at query
  # time (see filter_names_for). Dedupes the publicly-shown tag — see
  # Event#genre_list=.
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

  # File this genre into the tree under `parent` (a Genre or its id; nil detaches
  # it back to a root). A placed genre carries no disposition or alias, so clear
  # those. Rejects parenting a
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
  # unfiled. Set ignored_at, re-derive events.
  def ignore!
    transaction do
      update!(ignored_at: Time.current, hidden_at: nil, blocked_at: nil, canonical_id: nil, parent_id: nil)
    end
    recompute_events!
  end

  # "Hide": mark as non-music. Set hidden_at. Events carrying only this (and no
  # other non-hidden genre) drop out of public listings — see Event#hidden_by_genre?.
  def hide!
    transaction do
      update!(hidden_at: Time.current, ignored_at: nil, blocked_at: nil, canonical_id: nil, parent_id: nil)
    end
    recompute_events!
  end

  # "Block" scraper noise (never a real genre): set blocked_at, and strip this
  # genre's taggings off every event that carries it. The event itself stays
  # untouched and visible — only the junk tag goes. Event#genre_list= then keeps
  # it out on every future scrape, since scrapers re-tag by name.
  def block!
    transaction do
      update!(blocked_at: Time.current, ignored_at: nil, hidden_at: nil, canonical_id: nil, parent_id: nil)
    end
    # Snapshot ids first: recompute_visibility! drops this genre's tagging from each
    # event, shrinking the tagged_with set find_each would page over — which would
    # skip events and leave the blocked tag attached (cf. merge_into!).
    affected = Event.tagged_with(name, on: :genres).pluck(:id)
    Event.where(id: affected).find_each do |event|
      event.genre_list.remove(name)
      event.recompute_visibility! # persists the dropped tagging + re-derives visibility
    end
    update_columns(events_count: 0)
  end

  # Mark this genre as a semantic alias of `canonical` — a synonym the fingerprint
  # can't catch (e.g. "Elektronik" → "Electronic"). The alias is a query-time LINK,
  # not a data rewrite: events keep their own raw tag ("Elektronik") intact and the
  # genre filter resolves the alias at query time (see Genre.filter_names_for), so
  # source data stays untouched. Clearing the other marks keeps alias and
  # disposition/placement mutually exclusive. Idempotent. reconcile! keeps
  # events_count authoritative — the alias row retains its own taggings, so unlike
  # a blocked/hidden genre its count stays > 0.
  def merge_into!(canonical)
    raise ArgumentError, 'a genre cannot be merged into itself' if canonical.id == id

    update!(canonical_id: canonical.id, ignored_at: nil, hidden_at: nil, blocked_at: nil, parent_id: nil)
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
    Event.tagged_with(name, on: :genres).find_each(&:recompute_visibility!)
  end
end
