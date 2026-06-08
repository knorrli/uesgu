# Plain query object built from request params (see EventsController#index).
# Filters are no longer persisted, so this is not an ActiveRecord model.
class Filter
  attr_reader :queries, :style_list, :location_list, :genre_list, :date_ranges

  def initialize
    @queries = []
    @style_list = []
    @location_list = []
    @genre_list = []
    @date_ranges = []
  end

  def queries=(new_queries)
    @queries = parse(new_queries)
  end

  def style_list=(new_styles)
    @style_list = parse(new_styles)
  end

  def location_list=(new_locations)
    @location_list = parse(new_locations)
  end

  def genre_list=(new_genres)
    @genre_list = parse(new_genres)
  end

  def date_ranges=(new_date_ranges)
    ranges = parse(new_date_ranges)
    @date_ranges = ranges.sort_by { |r| index = Datepicker.preset.keys.index(r); [index ? 0 : 1, index] }
  end

  def ransack_query
    {
      g: [
        {
          title_or_subtitle_or_styles_name_or_genres_name_cont_any: queries,
          styles_name_in: style_list.presence,
          genres_name_in: genre_list.presence,
          m: Ransack::Constants::OR
        },
        {
          locations_name_in: location_list.presence
        },
        {}.tap do |date_group|
          if mapped_ranges = map_date_ranges(date_ranges).presence
            date_group[:start_date_between_any] = mapped_ranges
          else
            date_group[:start_date_gteq] = Date.current.beginning_of_day
          end
        end
      ]
    }
  end

  # Earliest concrete start date across the active date ranges (presets like
  # "next weekend" resolved to real dates), or nil when no date filter is set.
  # Lets the calendar jump to the month containing the filtered range.
  def earliest_date
    mapped = map_date_ranges(date_ranges).compact
    return nil if mapped.blank?

    mapped.map { |range| Date.iso8601(range.split(' - ').first) }.min
  end

  private

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
