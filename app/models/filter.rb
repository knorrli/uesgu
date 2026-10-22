class Filter
  attr_reader :queries, :genres, :location_list, :date_ranges

  def initialize
    @queries = []
    @genres = []
    @location_list = []
    @date_ranges = []
  end

  def self.build(queries: nil, genres: nil, location_list: nil, date_ranges: nil)
    new.tap do |filter|
      filter.queries = queries unless queries.nil?
      filter.genres = genres unless genres.nil?
      filter.location_list = location_list unless location_list.nil?
      filter.date_ranges = date_ranges unless date_ranges.nil?
    end
  end

  def queries=(new_queries)
    @queries = parse(new_queries)
  end

  def genres=(new_genres)
    @genres = names(new_genres)
  end

  def location_list=(new_locations)
    @location_list = names(new_locations)
  end

  def date_ranges=(new_date_ranges)
    presets = Datepicker.preset.keys
    @date_ranges = parse(new_date_ranges).select { |range| presets.include?(range) }.sort_by { |range| presets.index(range) }
  end

  def active?
    [queries, genres, location_list, date_ranges].any?(&:present?)
  end

  def expanded_genre_names
    return [] if genres.blank?

    Genre.filter_names_for(genres)
  end

  def ransack_query(including_past: false)
    {
      g: [
        {
          title_or_description_or_genres_name_cont_any: queries,
          genres_name_in: expanded_genre_names.presence,
          m: Ransack::Constants::OR
        },
        {
          locations_name_in: location_list.presence
        },
        {}.tap do |date_group|
          if mapped_ranges = map_date_ranges(date_ranges).presence
            date_group[:start_date_between_any] = mapped_ranges
            date_group[:start_date_gteq] = Date.current.beginning_of_day
          elsif !including_past
            date_group[:start_date_gteq] = Date.current.beginning_of_day
          end
        end
      ]
    }
  end

  private

  def parse(value)
    ActsAsTaggableOn.default_parser.new(value).parse
  end

  # ActsAsTaggableOn's parser splits on commas, and "Soul, Funk & R&B" is one genre.
  def names(value)
    return parse(value) unless value.is_a?(Array)

    value.flatten.map { |item| item.to_s.strip }.compact_blank
  end

  def map_date_ranges(date_ranges)
    presets = Datepicker.preset
    date_ranges.map do |range|
      start_date, end_date = presets[range][:values]
      "#{start_date} - #{end_date}"
    end
  end
end
