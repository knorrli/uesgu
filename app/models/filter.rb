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
    @genres = parse(new_genres)
  end

  def location_list=(new_locations)
    @location_list = parse(new_locations)
  end

  def date_ranges=(new_date_ranges)
    ranges = parse(new_date_ranges)
    @date_ranges = ranges.sort_by { |r| index = Datepicker.preset.keys.index(r); [index ? 0 : 1, index] }
  end

  def active?
    [queries, genres, location_list, date_ranges].any?(&:present?)
  end

  def expanded_genre_names
    return [] if genres.blank?

    Genre.filter_names_for(genres)
  end

  def ransack_query
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
            date_group[:start_date_gteq] = Date.current.beginning_of_day unless custom_range?
          else
            date_group[:start_date_gteq] = Date.current.beginning_of_day
          end
        end
      ]
    }
  end

  private

  def custom_range?
    date_ranges.any? { |range| !Datepicker.preset.key?(range) && range.to_s.match?(/\A\d{4}-\d{2}-\d{2} - \d{4}-\d{2}-\d{2}\z/) }
  end

  def parse(value)
    ActsAsTaggableOn.default_parser.new(value).parse
  end

  def map_date_ranges(date_ranges)
    return [] if date_ranges.blank?

    date_ranges.map do |range|
      if preset = Datepicker.preset[range]
        start_date, end_date = preset[:values]
        "#{start_date.to_date.iso8601} - #{end_date.to_date.iso8601}"
      else
        /\d{4}-\d{2}-\d{2}\s-\s\d{4}-\d{2}-\d{2}/.match?(range) ? range : nil
      end
    end
  end
end
