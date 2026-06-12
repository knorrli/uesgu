module Admin
  # Read-only browser over the scraped events table. Mirrors the genres index:
  # filter by visibility status, sort, free-text title search, paginate. Unlike
  # the public index (scoped to :visible), the admin sees everything.
  class EventsController < BaseController
    # "hidden" = non-music events suppressed from the public listing; "cancelled"
    # = called-off shows that stay listed publicly with a marker.
    STATUS_SCOPES = {
      'visible' => -> { Event.visible },
      'hidden' => -> { Event.where(hidden: true) },
      'cancelled' => -> { Event.cancelled }
    }.freeze

    # Newest first by default (the freshly scraped end of the table); 'title' is
    # the alphabetical lookup.
    SORT_SCOPES = {
      'date' => ->(scope) { scope.order(start_date: :desc) },
      'title' => ->(scope) { scope.order(:title) }
    }.freeze

    def index
      @status = STATUS_SCOPES.key?(params[:status]) ? params[:status] : 'all'
      @sort = SORT_SCOPES.key?(params[:sort]) ? params[:sort] : 'date'
      scope = @status == 'all' ? Event.all : STATUS_SCOPES[@status].call
      scope = scope.where('title ILIKE ?', "%#{params[:q]}%") if params[:q].present?
      @events = SORT_SCOPES[@sort].call(scope).includes(:locations, :styles).page(params[:page]).per(50)
    end
  end
end
