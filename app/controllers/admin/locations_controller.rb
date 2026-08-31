module Admin
  class LocationsController < BaseController
    include CatalogueBrowsing

    TYPES = %w[all venue locality canton].freeze
    SORTS = %w[name count].freeze

    def index
      @type = catalogue_param(:type, TYPES, default: "all")
      @sort = catalogue_param(:sort, SORTS, default: "name")

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

      @locations = Kaminari.paginate_array(locations).page(params[:page]).per(PAGE_SIZE)
    end
  end
end
