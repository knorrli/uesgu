module Admin
  class LocalitiesController < BaseController
    include CatalogueBrowsing

    STATUS_SCOPES = { "aliased" => :aliased, "unsettled" => :unsettled }.freeze
    SORT_SCOPES = { "name" => :by_name, "count" => :by_usage }.freeze

    def index
      @status = catalogue_param(:status, STATUS_SCOPES, default: "all")
      @sort = catalogue_param(:sort, SORT_SCOPES, default: "name")

      scope = @status == "all" ? Locality.all : Locality.public_send(STATUS_SCOPES[@status])
      scope = scope.where("name ILIKE ?", "%#{params[:q]}%") if params[:q].present?
      @localities = scope.public_send(SORT_SCOPES[@sort]).includes(:canonical).page(params[:page]).per(PAGE_SIZE)
    end

    def edit
      @locality = Locality.find(params[:id])
    end

    def merge
      locality = Locality.find(params[:id])
      locality.merge_into!(Locality.find(params.expect(locality: [:canonical_locality_id])[:canonical_locality_id]))
      redirect_to return_to
    rescue ArgumentError
      redirect_to edit_admin_locality_path(locality)
    end

    def unmerge
      Locality.find(params[:id]).unmerge!
      redirect_to return_to
    end

    private

    def return_to
      to = params[:return_to].to_s
      to.start_with?("/") ? to : admin_localities_path
    end
  end
end
