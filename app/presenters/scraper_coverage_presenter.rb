class ScraperCoveragePresenter
  Row = Data.define(:source, :events, :with_time, :with_description, :with_genre, :distinct_genres, :gaps) do
    def present? = events.positive?
    def time_pct = ratio(with_time)
    def description_pct = ratio(with_description)
    def genre_pct = ratio(with_genre)

    def pct(field)
      case field
      when :time     then time_pct
      when :description then description_pct
      when :genres   then genre_pct
      end
    end

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

  def field_gaps_by_source
    Scrapers::All.scrapers.values.each_with_object({}) do |klass, h|
      declared = klass.field_gaps
      h[klass.source_key] = declared if declared.any?
    end
  end

  def base_counts
    Event.where.not(data_source: nil).group(:data_source).pluck(
      :data_source,
      Arel.sql("COUNT(*)"),
      Arel.sql("COUNT(start_time)"),
      Arel.sql("COUNT(NULLIF(description, ''))")
    ).to_h { |source, total, time, sub| [source, [total, time, sub]] }
  end

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
