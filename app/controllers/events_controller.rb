class EventsController < ApplicationController
  allow_unauthenticated_access only: %i[ index ]
  before_action :require_admin, only: %i[ destroy ]
  before_action :set_event, only: %i[ destroy ]

  # GET /events
  def index
    @filter = Filter.new
    @filter.queries = params[:q].compact_blank if params[:q].present?
    @filter.location_list = params[:l] if params[:l].present?
    @filter.style_list = params[:s] if params[:s].present?
    @filter.date_ranges = params[:d].compact_blank if params[:d].present?

    @q = Event.ransack(@filter.ransack_query)
    @events = @q.result(distinct: true).order(start_date: :asc).page(params[:page])
  end

  # DELETE /events/1
  def destroy
    @event.destroy!
    redirect_to events_path, status: :see_other
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_event
    @event = Event.find(params.expect(:id))
  end
end
