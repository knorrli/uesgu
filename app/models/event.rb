class Event < ApplicationRecord
  acts_as_taggable_on :locations, :styles, :genres

  # The scrape run that first created this event (nil for events predating run
  # tracking, or whose run has since been pruned). Set once, on insert, by the
  # orchestrator — re-scrapes that only update the event leave it untouched.
  belongs_to :created_in_scrape_run, class_name: 'ScrapeRun', optional: true,
                                     inverse_of: :created_events

  # Users who bookmarked this event ("save this show"). class_name pinned because
  # the inflector singularizes "saves" → "safe".
  has_many :event_saves, class_name: 'EventSave', dependent: :destroy

  # The admin discard rule (if any) currently filtering this event from public
  # listings. Re-derived each scrape + on rule changes; nullified if the rule is
  # deleted (see DiscardRule). nil = not discarded.
  belongs_to :discarded_by_rule, class_name: 'DiscardRule', optional: true,
                                 inverse_of: :discarded_events

  # Event dedup (non-destructive): a duplicate points at its canonical (the
  # preferred source, PETZI). nil = this event IS canonical / standalone.
  # Re-derived each scrape by Scrapers::Dedup; bookmarks on a duplicate are
  # preserved (never deleted), the duplicate is just hidden from listings.
  belongs_to :canonical_event, class_name: 'Event', optional: true,
                               inverse_of: :duplicate_events
  has_many :duplicate_events, class_name: 'Event', foreign_key: :canonical_event_id,
                              dependent: :nullify, inverse_of: :canonical_event

  validates :title, :start_date, :url, presence: true

  # Public-facing events: non-music events (carrying a hidden genre, with no
  # music style) are hidden, events matched by an admin discard rule are filtered
  # out, dismissed events are gone for good, and a duplicate (merged into a
  # canonical) is suppressed in favour of its canonical. Admin/curation views skip this.
  scope :visible, -> { kept.where(hidden: false, discarded_by_rule_id: nil, canonical_event_id: nil) }
  scope :duplicates, -> { where.not(canonical_event_id: nil) }
  scope :canonical, -> { where(canonical_event_id: nil) }
  scope :discarded, -> { kept.where.not(discarded_by_rule_id: nil) }
  scope :cancelled, -> { where.not(cancelled_at: nil) }

  # Dismiss is a sticky, admin-driven soft-delete: a dismissed event drops out of
  # every public listing AND is never resurrected by a re-scrape (the scraper
  # skips it — see Scrapers::Agent#process_events), unlike `hidden`/`cancelled`
  # which are re-derived from the source each run.
  scope :kept, -> { where(dismissed_at: nil) }
  scope :dismissed, -> { where.not(dismissed_at: nil) }

  # Cancelled events stay listed (with a marker) rather than vanishing, so a
  # follower sees the show was called off. Derived from the source each scrape.
  def cancelled?
    cancelled_at.present?
  end

  def dismissed?
    dismissed_at.present?
  end

  # Filtered out by an admin discard rule (re-derived, reversible) — distinct
  # from the sticky, per-event dismiss above.
  def discarded?
    discarded_by_rule_id.present?
  end

  # Soft-delete this event so it never reappears, even on re-scrape. Idempotent —
  # re-dismissing keeps the original timestamp.
  def dismiss!
    update!(dismissed_at: Time.current) unless dismissed?
  end

  # Lift a dismissal: the event reappears in public listings AND re-scrapes
  # resume updating it from source. Idempotent — a no-op on a kept event.
  def undismiss!
    update!(dismissed_at: nil) if dismissed?
  end

  # Admin manual merge: mark this event a duplicate of `canonical` and PIN the
  # link so the next sweep's dedup leaves it alone. Used to collapse a pair the
  # fuzzy matcher missed (titles drifted between PETZI and the venue source).
  def merge_into!(canonical)
    raise ArgumentError, 'cannot merge an event into itself' if canonical.id == id

    update!(canonical_event_id: canonical.id)
    lock_field!('canonical_event')
  end

  # Admin manual un-merge: declare this event standalone and PIN that decision, so
  # dedup won't re-merge it. Used to split a pair the fuzzy matcher wrongly joined.
  def mark_standalone!
    update!(canonical_event_id: nil)
    lock_field!('canonical_event')
  end

  # Scalar fields an admin may edit and lock against the scraper. Tracked by
  # ActiveRecord dirty-checking, so the controller locks exactly what changed.
  # `url` is the immutable upsert key, so it's deliberately absent.
  OVERRIDABLE_FIELDS = %w[title subtitle start_date start_time].freeze

  # Tag lists an admin may pin against the scraper. Not real columns (so they
  # never show up in `changed`), but they sit in overridden_fields alongside the
  # scalars and gate the scrape the same way (see Scrapers::Agent#build_event).
  # A pinned genre list keeps its derived styles/visibility, recomputed from it
  # — styles and the `hidden`/`cancelled` flags stay source-derived projections.
  OVERRIDABLE_TAG_FIELDS = %w[genres].freeze

  # The dedup link an admin may pin: a manual merge/un-merge that Scrapers::Dedup
  # must not re-derive on the next sweep (fuzzy matching can miss or mis-pair when
  # titles drift between the PETZI and venue sources).
  OVERRIDABLE_LINK_FIELDS = %w[canonical_event].freeze

  # Everything an admin may pin: the allowlist lock_field! guards and the set the
  # admin UI lists as revertible.
  LOCKABLE_FIELDS = (OVERRIDABLE_FIELDS + OVERRIDABLE_TAG_FIELDS + OVERRIDABLE_LINK_FIELDS).freeze

  # `overridden_fields` is the field-level sibling of `dismissed_at`: a name
  # listed here is admin-owned, so the re-scrape leaves that column untouched
  # (see Scrapers::Agent#build_event) instead of re-deriving it from source.
  def overridden?(field)
    overridden_fields.include?(field.to_s)
  end

  # Lock a field to its current (admin-edited) value. Idempotent; ignores any
  # name outside LOCKABLE_FIELDS so the list can never hold a source-owned
  # column.
  def lock_field!(field)
    field = field.to_s
    return unless LOCKABLE_FIELDS.include?(field) && !overridden?(field)

    update!(overridden_fields: overridden_fields + [field])
  end

  # Release a field back to the scraper; the next run refills it from source.
  def release_field!(field)
    field = field.to_s
    return unless overridden?(field)

    update!(overridden_fields: overridden_fields - [field])
  end

  # Genre-model ids matching this event's current genre tags (by fingerprint) —
  # the selection the admin override combobox shows. ensure! guarantees a Genre
  # row per tagged genre on every scrape (Scrapers::Agent#event_styles), so this
  # never silently drops one. The matching setter lives in the controller, which
  # maps the submitted ids back to names through genre_list=.
  def override_genre_ids
    Genre.where(fingerprint: genre_list.map { |name| Genre.fingerprint_for(name) }).pluck(:id)
  end

  def self.ransackable_attributes(auth_object = nil)
    ['title', 'subtitle', 'start_date']
  end

  def self.ransackable_associations(auth_object = nil)
    ['taggings', 'locations', 'styles', 'genres']
  end

  # The venue location among this event's flat location tags (the rest are
  # city/canton). See Location for how the type is derived.
  def venue
    locations.detect { |location| Location.venue?(location.name) }
  end

  def to_s
    [
      start_date.strftime('%y-%m-%d'),
      title.truncate(40),
      subtitle&.truncate(20),
      locations.map(&:name).join(', ')
    ].compact_blank.join(' || ')
  end

  # Normalize scraped genres at the source — the central choke point for every
  # scraper, re-applied each run. Lets AATO parse the input first, then (1)
  # canonicalizes each name to its collapsed/aliased spelling so the stored tag
  # is deduped, and (2) strips blocked genres (scraper noise like country codes
  # or artist-name fragments) by fingerprint so they never get tagged.
  def genre_list=(value)
    super
    genre_list.replace(Genre.canonicalize_names(genre_list))
    blocked = Genre.blocked_fingerprints
    genre_list.reject! { |name| blocked.include?(Genre.fingerprint_for(name)) } if blocked.any?
  end

  # Styles are a derived projection of this event's genres: the union of the
  # styles each genre maps to, matched by fingerprint (Genre.styles_for — the
  # same path the scraper uses). Recomputing from source (rather than nudging the
  # style list incrementally) is what keeps re-mapping a genre correct even when
  # several genres on the same event point at the same style.
  def recompute_styles!
    Genre.ensure!(genre_list)
    self.style_list = Genre.styles_for(genre_list)
    self.hidden = hidden_by_genre?
    save!
  end

  # Non-music: every genre the event carries is hidden-dispositioned, so it has no
  # genre worth showing. Any single non-hidden genre (a real music genre) keeps it
  # visible — a "reading + concert" stays up — and an event with no genres at all
  # stays visible too. Reads genre_list directly off genre dispositions (no
  # dependence on the soon-removed style layer), so recompute_styles! and the
  # scrape path (Scrapers::Agent#build_event) derive `hidden` identically.
  def hidden_by_genre?
    fingerprints = genre_list.map { |name| Genre.fingerprint_for(name) }
    return false if fingerprints.empty?

    hidden = Genre.hidden.where(fingerprint: fingerprints).pluck(:fingerprint).to_set
    fingerprints.all? { |fingerprint| hidden.include?(fingerprint) }
  end
end
