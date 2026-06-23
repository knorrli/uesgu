module Admin
  # Read-only browser over the location tags that classify events. Locations have
  # no table of their own — the type (venue / city / canton) is derived from the
  # scrapers via the Location model. Mirrors the genres index idiom: filter by
  # type, sort, search, paginate. The set is small, so it's handled in Ruby.
  class LocationsController < BaseController
    TYPES = %w[all venue city canton].freeze
    SORTS = %w[name count].freeze

    def index
      @type = TYPES.include?(params[:type]) ? params[:type] : "all"
      @sort = SORTS.include?(params[:sort]) ? params[:sort] : "name"

      locations = Location.usage
      locations.select! { |loc| loc[:type].to_s == @type } unless @type == "all"
      if params[:q].present?
        needle = params[:q].downcase
        locations.select! { |loc| loc[:name].downcase.include?(needle) }
      end

      locations = if @sort == "count"
                    locations.sort_by { |loc| [-loc[:count], loc[:name].downcase] }
      else
                    locations.sort_by { |loc| loc[:name].downcase }
      end

      @locations = Kaminari.paginate_array(locations).page(params[:page]).per(50)
    end
  end
end
