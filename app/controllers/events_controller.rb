class EventsController < ApplicationController
  allow_unauthenticated_access only: %i[ index ]
  before_action :require_admin, only: %i[ destroy ]
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
    @q = Event.visible.ransack(@filter.ransack_query)

    events = @q.result(distinct: true).order(start_date: :asc)
    @has_results = events.exists?
    @events = events.includes(:locations, :genres).page(params[:page])
  end

  def destroy
    @event.dismiss!
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
      if params[:filtered].present?
        redirect_to events_path(request.query_parameters.except("filtered").symbolize_keys)
        return true
      end
    elsif (stored = stored_filter)
      redirect_to events_path(request.query_parameters.merge(stored).symbolize_keys)
      return true
    end
    false
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
