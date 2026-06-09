class Event < ApplicationRecord
  acts_as_taggable_on :locations, :styles, :genres

  validates :title, :start_date, :url, presence: true

  # Public-facing events: non-music events (carrying a hidden genre, with no
  # music style) are hidden. Admin/curation views deliberately skip this scope.
  scope :visible, -> { where(hidden: false) }

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

  # Drop blocked genres (scraper noise like country codes or artist-name
  # fragments) at the source, so they never get tagged. Central choke point for
  # every scraper — re-applied each run, since scrapers re-tag by name and
  # remove_unused_tags can't outlive the next scrape. Lets AATO parse the input
  # first, then strips the blocklisted names off the in-memory tag list.
  def genre_list=(value)
    super
    blocked = Genre.blocked_names
    genre_list.reject! { |name| blocked.include?(name.downcase) } if blocked.any?
  end

  # Styles are a derived projection of this event's genres: the union of the
  # styles each genre maps to. Recomputing from source (rather than nudging the
  # style list incrementally) is what keeps re-mapping a genre correct even when
  # several genres on the same event point at the same style.
  def recompute_styles!
    Genre.ensure!(genre_list)
    # Match case-insensitively: scraped genre casing varies, while a genre's
    # canonical name (e.g. from the taxonomy import) may differ in case.
    lowered = genre_list.map { |name| name.to_s.downcase }
    style_names = Style.joins(:genres)
                       .where('lower(genres.name) IN (?)', lowered.presence || [nil])
                       .distinct.pluck(:name)
    self.style_list = style_names
    # Non-music: carries a hidden genre and has no music style. A real style
    # always wins (a "concert + reading" stays visible).
    self.hidden = style_names.empty? &&
                  Genre.hidden.where('lower(name) IN (?)', lowered.presence || [nil]).exists?
    save!
  end
end
