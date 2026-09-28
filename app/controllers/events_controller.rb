class EventsController < ApplicationController
  allow_unauthenticated_access only: %i[ index ]
  before_action -> { require_permission(:curate_events) }, only: %i[ destroy ]
  before_action :set_event, only: %i[ destroy ]

  FILTER_KEYS = %i[q g l d].freeze
  FILTER_COOKIE = :events_filter

  def index
    return if redirect_to_canonical_filter

    @filter = build_filter
    if current_user
      @saved_filter = current_user.saved_filters.matching(SavedFilter.fingerprint_for(@filter))
    end
    @saved_filters = current_user.saved_filters.order(:created_at) if current_user
    @applied_saved_filter = Current.session&.applied_saved_filter unless @saved_filter
    @q = Event.visible.ransack(@filter.ransack_query)

    excluded_genres = ExcludedGenres.for(current_user, picked: @filter.genres)
    matching = @q.result(distinct: true)
    events = excluded_genres.apply(matching)
    @days = EventDays.new(events)
    return if redirect_to_canonical_day

    excluded = excluded_genres.excluded_from(matching)
    @excluded_count = (@day ? excluded.where(start_date: @day) : excluded).count
    @events = events.where(start_date: @day).includes(:locations, :genres)
  end

  def destroy
    ActionLog.track("event.dismiss", @event) { @event.dismiss! }
    redirect_to delete_return_path, status: :see_other
  end

  private

  def delete_return_path
    target = params[:return_to].to_s
    target.match?(%r{\A/(?!/)}) ? target : events_path
  end

  def build_filter
    Filter.build(
      queries: params[:q].present? ? Array(params[:q]).compact_blank : nil,
      genres: params[:g].presence,
      location_list: params[:l].presence,
      date_ranges: params[:d].present? ? Array(params[:d]).compact_blank : nil
    )
  end

  def redirect_to_canonical_filter
    if explicit_filter_request?
      sync_filter_cookie
      track_applied_saved_filter
      if params[:filtered].present? || params[:applied].present?
        redirect_to events_path(request.query_parameters.except("filtered", "applied").symbolize_keys)
        return true
      end
    elsif (stored = stored_filter)
      redirect_to events_path(request.query_parameters.merge(stored).symbolize_keys)
      return true
    end
    false
  end

  def redirect_to_canonical_day
    @day = params[:day].present? ? @days.resolve(requested_day) : @days.default
    canonical = request.query_parameters.except("page", "day")
    canonical["day"] = @day.iso8601 if params[:day].present? && @day
    return false if canonical == request.query_parameters

    redirect_to events_path(canonical.symbolize_keys)
    true
  end

  def requested_day
    Date.iso8601(params[:day].to_s)
  rescue Date::Error
    nil
  end

  def track_applied_saved_filter
    return unless Current.session

    if params[:applied].present?
      Current.session.update!(applied_saved_filter: current_user.saved_filters.find_by(id: params[:applied]))
    elsif FILTER_KEYS.none? { |key| params[key].present? }
      Current.session.update!(applied_saved_filter: nil)
    end
  end

  def explicit_filter_request?
    params[:filtered].present? || FILTER_KEYS.any? { |key| params[key].present? }
  end

  def sync_filter_cookie
    payload = FILTER_KEYS.each_with_object({}) do |key, acc|
      values = Array(params[key]).compact_blank
      acc[key] = values if values.any?
    end

    if payload.any?
      cookies[FILTER_COOKIE] = {
        value: payload.to_json, expires: 1.year, same_site: :lax, path: "/", httponly: true
      }
    else
      cookies.delete(FILTER_COOKIE, path: "/")
    end
  end

  def stored_filter
    raw = cookies[FILTER_COOKIE]
    return nil if raw.blank?

    data = JSON.parse(raw)
    return nil unless data.is_a?(Hash)

    filter = FILTER_KEYS.each_with_object({}) do |key, acc|
      values = Array(data[key.to_s]).compact_blank
      acc[key.to_s] = values if values.any?
    end
    filter.presence
  rescue JSON::ParserError
    nil
  end

  def set_event
    @event = Event.find(params.expect(:id))
  end
end
