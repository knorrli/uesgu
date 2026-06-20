# Backs /admin/scraper_coverage: a per-scraper matrix of how *complete* the data
# each scraper collects is — what share of its events carry a start time, a
# subtitle, and at least one genre, plus how many distinct genres it surfaces.
#
# Computed live from the events table (grouped by Event#data_source, which every
# scraper stamps via source_key), so it can never drift the way a hand-written
# capability doc would: a scraper that breaks and stops collecting genres shows
# its genre% fall the next time the page is opened. Every known scraper is listed
# even with zero events, so a venue that's gone silent stands out too.
class ScraperCoveragePresenter
  Row = Data.define(:source, :events, :with_time, :with_subtitle, :with_genre, :distinct_genres) do
    def present? = events.positive?
    def time_pct = ratio(with_time)
    def subtitle_pct = ratio(with_subtitle)
    def genre_pct = ratio(with_genre)

    def ratio(count)
      return 0 if events.zero?

      (100.0 * count / events).round
    end
  end

  def rows
    @rows ||= build_rows
  end

  # Anything to show? (Registry may be empty until scrapers load; events are the
  # real signal.)
  def any?
    rows.any?(&:present?)
  end

  private

  def build_rows
    base   = base_counts
    genres = genre_counts
    sources = (Scrapers::All.scrapers.keys + base.keys).uniq.sort_by(&:downcase)

    sources.map do |source|
      total, with_time, with_subtitle = base.fetch(source, [0, 0, 0])
      with_genre, distinct = genres.fetch(source, [0, 0])
      Row.new(source:, events: total, with_time:, with_subtitle:,
              with_genre:, distinct_genres: distinct)
    end
  end

  # [total, with_time, with_subtitle] per data_source in one grouped pass. A NULL
  # or empty subtitle / a date-only event (no start_time) simply doesn't count.
  def base_counts
    Event.where.not(data_source: nil).group(:data_source).pluck(
      :data_source,
      Arel.sql('COUNT(*)'),
      Arel.sql('COUNT(start_time)'),
      Arel.sql("COUNT(NULLIF(subtitle, ''))")
    ).to_h { |source, total, time, sub| [source, [total, time, sub]] }
  end

  # [events_with_a_genre, distinct_genres] per data_source. LEFT JOIN onto the
  # AATO genre taggings so a source with no genres still reports zero rather than
  # dropping out of the result set.
  def genre_counts
    Event.where.not(data_source: nil)
         .joins("LEFT JOIN taggings ON taggings.taggable_type = 'Event' " \
                "AND taggings.taggable_id = events.id AND taggings.context = 'genres'")
         .group(:data_source)
         .pluck(
           :data_source,
           Arel.sql('COUNT(DISTINCT CASE WHEN taggings.id IS NOT NULL THEN events.id END)'),
           Arel.sql('COUNT(DISTINCT taggings.tag_id)')
         ).to_h { |source, with_genre, distinct| [source, [with_genre, distinct]] }
  end
end
