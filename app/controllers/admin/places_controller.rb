module Admin
  class PlacesController < BaseController
    include CatalogueBrowsing

    STATUS_SCOPES = { "aliased" => :aliased }.freeze
    SORTS = %w[name count].freeze

    def index
      @status = catalogue_param(:status, STATUS_SCOPES, default: "all")
      @sort = catalogue_param(:sort, SORTS, default: "name")
      @counts = Location.usage.to_h { |row| [row[:name], row[:count]] }

      scope = @status == "all" ? Place.all : Place.public_send(STATUS_SCOPES[@status])
      scope = scope.where("name ILIKE ?", "%#{params[:q]}%") if params[:q].present?
      @places = Kaminari.paginate_array(sorted(scope.includes(:canonical).to_a))
                        .page(params[:page]).per(PAGE_SIZE)
    end

    def edit
      @place = Place.find(params[:id])
      @count = usage_count(@place)
    end

    def update
      @place = Place.find(params[:id])
      @count = usage_count(@place)
      attrs = params.expect(place: %i[name url])
      @place.url = attrs[:url].presence if attrs.key?(:url)
      return redirect_to edit_admin_place_path(@place) if @place.rename!(attrs[:name])

      render :edit, status: :unprocessable_entity
    end

    def merge
      place = Place.find(params[:id])
      place.merge_into!(Place.find(params.expect(place: [:canonical_place_id])[:canonical_place_id]))
      redirect_to return_to
    rescue ArgumentError
      redirect_to edit_admin_place_path(place)
    end

    def unmerge
      Place.find(params[:id]).unmerge!
      redirect_to return_to
    end

    private

    def usage_count(place)
      Location.usage.find { |row| row[:name] == place.name }&.fetch(:count) || 0
    end

    def sorted(places)
      return places.sort_by { |place| place.name.downcase } unless @sort == "count"

      places.sort_by { |place| [-@counts[place.name].to_i, place.name.downcase] }
    end

    def return_to
      to = params[:return_to].to_s
      to.start_with?("/") ? to : admin_places_path
    end
  end
end
