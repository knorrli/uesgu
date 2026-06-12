class Event < ApplicationRecord
  acts_as_taggable_on :locations, :styles, :genres

  # The scrape run that first created this event (nil for events predating run
  # tracking, or whose run has since been pruned). Set once, on insert, by the
  # orchestrator — re-scrapes that only update the event leave it untouched.
  belongs_to :created_in_scrape_run, class_name: 'ScrapeRun', optional: true,
                                     inverse_of: :created_events

  validates :title, :start_date, :url, presence: true

  # Public-facing events: non-music events (carrying a hidden genre, with no
  # music style) are hidden. Admin/curation views deliberately skip this scope.
  scope :visible, -> { where(hidden: false) }
  scope :cancelled, -> { where.not(cancelled_at: nil) }

  # Cancelled events stay listed (with a marker) rather than vanishing, so a
  # follower sees the show was called off. Derived from the source each scrape.
  def cancelled?
    cancelled_at.present?
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

  # Non-music: carries a hidden-dispositioned genre and has no music style (a real
  # style always wins — a "concert + reading" stays visible). Reads the current
  # genre_list + style_list, so both recompute_styles! and the scrape path
  # (Scrapers::Agent#build_event) derive `hidden` identically.
  def hidden_by_genre?
    fingerprints = genre_list.map { |name| Genre.fingerprint_for(name) }.presence || ['']
    style_list.empty? && Genre.hidden.where(fingerprint: fingerprints).exists?
  end
end
