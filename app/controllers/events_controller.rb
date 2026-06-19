class EventsController < ApplicationController
  include ListingViewMode

  allow_unauthenticated_access only: %i[ index ]
  before_action :require_admin, only: %i[ destroy ]
  before_action :set_event, only: %i[ destroy ]

  # GET /events
  def index
    @filter = build_filter
    # A logged-in user gets a "notify me about this filter" bell; if they already
    # have a rule for exactly this filter set, it's lit and links to that rule
    # instead of creating a clone (see _notify_button + NotificationRule.matching).
    if current_user && @filter.subscribable?
      @notify_rule = current_user.notification_rules.matching(NotificationRule.fingerprint_for(@filter))
    end
    @q = Event.visible.ransack(@filter.ransack_query)

    @view = resolve_view(session_key: :events_view, account_attr: :events_view)

    events = @q.result(distinct: true).order(start_date: :asc)
    if @view == 'calendar'
      @calendar_interactive = true
      # Focus order: explicit month nav (start_date) > the month of an active
      # date filter (e.g. "next weekend" may fall in another month) > today.
      @calendar_start = (Date.parse(params[:start_date]) rescue nil) || @filter.earliest_date || Date.current
      # simple_calendar navigates via params[:start_date]; load the focused
      # month plus a week of padding so adjacent-month grid cells are covered.
      @events = events.includes(:locations, :styles).where(start_date: (@calendar_start.beginning_of_month - 7)..(@calendar_start.end_of_month + 7))
      # Followed locations surface venues first in each cell; the per-day heart
      # marker (locations or styles) is computed in the calendar partial.
      @favorites = current_user&.location_list.to_a
      # A day's expansion is URL state (params[:day]), so the server renders the
      # open day's detail inline in the grid — linkable, reload-safe, and the
      # source of truth (no client-side drawer to preserve). See #day_events.
      @open_day = (Date.parse(params[:day]) rescue nil) if params[:day].present?
      @open_day_events = day_events(@open_day) if @open_day
    else
      @events = events.includes(:locations, :styles, :genres).page(params[:page])
    end
  end

  # DELETE /events/1 — a sticky soft-delete (see Event#dismiss!): the event drops
  # out of every listing and stays gone across re-scrapes, rather than being hard-
  # deleted and recreated by the next scrape of a source that still lists it.
  def destroy
    @event.dismiss!
    redirect_to events_path, status: :see_other
  end

  private

  # Events on a single day, honouring the active filter (queries/locations/
  # styles) but overriding its date floor so past days in the visible month
  # still resolve. Used to render the calendar's inline day expansion.
  def day_events(date)
    filter = build_filter
    filter.date_ranges = ["#{date.iso8601} - #{date.iso8601}"]
    Event.visible.ransack(filter.ransack_query)
         .result(distinct: true)
         .includes(:locations, :styles, :genres)
         .order(:start_time, :title)
  end

  def build_filter
    # Array() wraps a hand-typed scalar (?q=foo) into a list so compact_blank
    # works; the UI always sends arrays, so this only guards the manual-URL case.
    # Anything absent stays nil, so Filter.build leaves that list at its default.
    Filter.build(
      queries: params[:q].present? ? Array(params[:q]).compact_blank : nil,
      location_list: params[:l].presence,
      style_list: params[:s].presence,
      genre_list: params[:g].presence,
      date_ranges: params[:d].present? ? Array(params[:d]).compact_blank : nil
    )
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_event
    @event = Event.find(params.expect(:id))
  end
end
