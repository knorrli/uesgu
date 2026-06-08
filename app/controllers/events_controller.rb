class EventsController < ApplicationController
  allow_unauthenticated_access only: %i[ index day ]
  before_action :require_admin, only: %i[ destroy ]
  before_action :set_event, only: %i[ destroy ]

  # GET /events
  def index
    @filter = build_filter
    @q = Event.ransack(@filter.ransack_query)

    # Remember the chosen view across requests (filter changes, pagination) so
    # it persists until the visitor explicitly switches it again. Session is the
    # primary store; for logged-in users we also mirror it onto their account so
    # the preference follows them to a fresh session / another device.
    @view = params[:view].presence || session[:events_view] || current_user&.events_view || 'list'
    @view = 'list' unless @view == 'calendar'
    session[:events_view] = @view
    current_user.update_column(:events_view, @view) if current_user && current_user.events_view != @view

    events = @q.result(distinct: true).order(start_date: :asc)
    if @view == 'calendar'
      # Focus order: explicit month nav (start_date) > the month of an active
      # date filter (e.g. "next weekend" may fall in another month) > today.
      @calendar_start = (Date.parse(params[:start_date]) rescue nil) || @filter.earliest_date || Date.current
      # simple_calendar navigates via params[:start_date]; load the focused
      # month plus a week of padding so adjacent-month grid cells are covered.
      @events = events.includes(:locations, :styles).where(start_date: (@calendar_start.beginning_of_month - 7)..(@calendar_start.end_of_month + 7))
      # Followed locations surface venues first in each cell; the per-day heart
      # marker (locations or styles) is computed in the calendar partial.
      @favorites = current_user&.location_list.to_a
    else
      @events = events.includes(:locations, :styles, :genres).page(params[:page])
    end
  end

  # GET /events/day?date=YYYY-MM-DD — a single day's events, rendered into the
  # calendar's day-detail Turbo Frame (full detail, same partial as the list).
  def day
    @date = (Date.parse(params[:date]) rescue Date.current)
    @filter = build_filter
    # Constrain to the clicked day, overriding the default "today onward" floor
    # so past days in the visible month still show their events.
    @filter.date_ranges = ["#{@date.iso8601} - #{@date.iso8601}"]

    @q = Event.ransack(@filter.ransack_query)
    @events = @q.result(distinct: true).includes(:locations, :styles, :genres).order(:start_time, :title)
  end

  # DELETE /events/1
  def destroy
    @event.destroy!
    redirect_to events_path, status: :see_other
  end

  private

  def build_filter
    Filter.new.tap do |filter|
      filter.queries = params[:q].compact_blank if params[:q].present?
      filter.location_list = params[:l] if params[:l].present?
      filter.style_list = params[:s] if params[:s].present?
      filter.date_ranges = params[:d].compact_blank if params[:d].present?
    end
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_event
    @event = Event.find(params.expect(:id))
  end
end
