# Backs /admin/scraper_coverage: a per-scraper matrix of how *complete* the data
# each scraper collects is — what share of its events carry a start time, a
# description, and at least one genre, plus how many distinct genres it surfaces.
#
# Computed live from the events table (grouped by Event#data_source, which every
# scraper stamps via source_key), so it can never drift the way a hand-written
# capability doc would: a scraper that breaks and stops collecting genres shows
# its genre% fall the next time the page is opened. Every known scraper is listed
# even with zero events, so a venue that's gone silent stands out too.
class ScraperCoveragePresenter
  Row = Data.define(:source, :events, :with_time, :with_description, :with_genre, :distinct_genres, :gaps) do
    def present? = events.positive?
    def time_pct = ratio(with_time)
    def description_pct = ratio(with_description)
    def genre_pct = ratio(with_genre)

    # The fill-rate for one coverage field, by its gap key (:time/:description/:genres).
    def pct(field)
      case field
      when :time     then time_pct
      when :description then description_pct
      when :genres   then genre_pct
      end
    end

    # The declared "this source can't provide it" reason for a coverage field —
    # but only while the field is genuinely empty. If real data has shown up
    # (pct > 0) the live number wins and the gap is ignored, so a stale
    # declaration can never mask data the scraper actually collected. nil for a
    # fillable field or an undeclared source.
    def gap_for(field)
      return nil unless pct(field).zero?

      gaps[field]
    end

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
    gaps   = field_gaps_by_source
    sources = (Scrapers::All.scrapers.keys + base.keys).uniq.sort_by(&:downcase)

    sources.map do |source|
      total, with_time, with_description = base.fetch(source, [0, 0, 0])
      with_genre, distinct = genres.fetch(source, [0, 0])
      Row.new(source:, events: total, with_time:, with_description:,
              with_genre:, distinct_genres: distinct,
              gaps: gaps.fetch(source, {}))
    end
  end

  # source string (Event#data_source, i.e. each scraper's source_key) → the
  # coverage fields it declares it structurally cannot fill. Read live from the
  # registry (Scrapers::Agent.field_gaps), so a declaration can never drift from
  # the scraper that makes it. Keyed by source_key, which is what data_source
  # stores — OLE's source_key ("OLE:Bewegungsmelder") differs from its
  # demodulized class name, so we must not key by the latter.
  def field_gaps_by_source
    Scrapers::All.scrapers.values.each_with_object({}) do |klass, h|
      declared = klass.field_gaps
      h[klass.source_key] = declared if declared.any?
    end
  end

  # [total, with_time, with_description] per data_source in one grouped pass. A NULL
  # or empty description / a date-only event (no start_time) simply doesn't count.
  def base_counts
    Event.where.not(data_source: nil).group(:data_source).pluck(
      :data_source,
      Arel.sql("COUNT(*)"),
      Arel.sql("COUNT(start_time)"),
      Arel.sql("COUNT(NULLIF(description, ''))")
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
           Arel.sql("COUNT(DISTINCT CASE WHEN taggings.id IS NOT NULL THEN events.id END)"),
           Arel.sql("COUNT(DISTINCT taggings.tag_id)")
         ).to_h { |source, with_genre, distinct| [source, [with_genre, distinct]] }
  end
end
