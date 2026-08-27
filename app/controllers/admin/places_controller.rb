module Admin
  # Curation for the captured venues. The locations browser next door lists every
  # location TAG (venue / locality / canton) as derived usage; this lists the place
  # rows themselves, because combining two spellings of one venue needs something with
  # an id to point at. Mirrors the localities index idiom: filter by status, sort,
  # search, paginate.
  #
  # Counts come from the taggings rather than a column — a place has no reconcile pass
  # to maintain one — so the sort happens in Ruby over a table that stays small.
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
      @count = Location.usage.find { |row| row[:name] == @place.name }&.fetch(:count) || 0
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

    def sorted(places)
      return places.sort_by { |place| place.name.downcase } unless @sort == "count"

      places.sort_by { |place| [-@counts[place.name].to_i, place.name.downcase] }
    end

    # Constrained to internal paths so the round-tripped value can't be turned into
    # an open redirect.
    def return_to
      to = params[:return_to].to_s
      to.start_with?("/") ? to : admin_places_path
    end
  end
end
