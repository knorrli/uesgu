module Admin
  # Curation for the towns. The locations browser next door lists every location TAG
  # (venue / locality / canton) as derived usage; this lists the locality rows
  # themselves, because combining two spellings needs something with an id to point
  # at. Mirrors the genres index idiom: filter by status, sort, search, paginate.
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

    # Both actions re-derive the table, which is a full pass over the registry, the
    # places and the location taggings — cheap at this size, and it keeps the counts
    # on the page the admin lands back on true.
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

    # Constrained to internal paths so the round-tripped value can't be turned into
    # an open redirect.
    def return_to
      to = params[:return_to].to_s
      to.start_with?("/") ? to : admin_localities_path
    end
  end
end
