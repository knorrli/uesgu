class EventsController < ApplicationController
  allow_unauthenticated_access only: %i[ index ]
  before_action :require_admin, only: %i[ destroy ]
  before_action :set_event, only: %i[ destroy ]

  # Filter persistence: the last applied feed filter is remembered in a per-device
  # cookie so it survives leaving the page and coming back (a hop to settings, a
  # return visit) without re-picking it. The URL stays the single source of truth —
  # a plain visit with a remembered filter REDIRECTS to that filter's URL (see
  # #redirect_to_canonical_filter), so the address bar always reflects what's shown.
  # Counted in the cookie notice copy (now "three").
  FILTER_KEYS = %i[q g l d].freeze
  FILTER_COOKIE = :events_filter

  def index
    return if redirect_to_canonical_filter

    @filter = build_filter
    # @saved_filter is the saved filter matching this exact filter set, if any:
    # present → the saved-filters menu's funnel is lit (filled) and its top item
    # edits that filter; nil → the menu offers to save the active filter as a new
    # draft (see _saved_filters_menu + SavedFilter.matching).
    if current_user
      @saved_filter = current_user.saved_filters.matching(SavedFilter.fingerprint_for(@filter))
    end
    # The chip-row saved-filters menu (signed-in only) lists these to apply: each
    # option carries the full events URL for that saved filter, so picking one
    # navigates straight there (shareable). See _saved_filters_menu.
    @saved_filters = current_user.saved_filters.order(:created_at) if current_user
    @q = Event.visible.ransack(@filter.ransack_query)

    events = @q.result(distinct: true).order(start_date: :asc)
    # Whether the filter matches anything at all — a filter-level fact, not the
    # current page's slice, so paging past the last result can't turn the
    # empty-state on.
    @has_results = events.exists?
    @events = events.includes(:locations, :genres).page(params[:page])
  end

  # DELETE /events/1 — a sticky soft-delete (see Event#dismiss!): the event drops
  # out of every listing and stays gone across re-scrapes, rather than being hard-
  # deleted and recreated by the next scrape of a source that still lists it.
  def destroy
    @event.dismiss!
    redirect_to delete_return_path, status: :see_other
  end

  private

  # Where a delete lands. A delete fired from the genre-curation queue passes its
  # own path as return_to so the admin stays in the curation flow instead of being
  # bounced to the public feed; the feed's own delete passes nothing and falls back
  # here. Only same-origin relative paths are honoured (a leading single slash, not
  # "//host") — never redirect off-site from a param.
  def delete_return_path
    target = params[:return_to].to_s
    target.match?(%r{\A/(?!/)}) ? target : events_path
  end

  def build_filter
    # Array() wraps a hand-typed scalar (?q=foo) into a list so compact_blank
    # works; the UI always sends arrays, so this only guards the manual-URL case.
    # Anything absent stays nil, so Filter.build leaves that list at its default.
    Filter.build(
      queries: params[:q].present? ? Array(params[:q]).compact_blank : nil,
      genres: params[:g].presence,
      location_list: params[:l].presence,
      date_ranges: params[:d].present? ? Array(params[:d]).compact_blank : nil
    )
  end

  # Keep the URL the single source of truth for the active filter, with the cookie
  # as its memory. Returns true (and the action stops) if it issued a redirect.
  #
  #   • Explicit filter action — the filter form's `filtered` marker, or a shared
  #     q/g/l/d link — syncs the cookie to the URL. If the `filtered` marker is
  #     present we then redirect to drop it, so the committed URL is clean.
  #   • Plain visit (home link, back from settings, a bookmark) with a remembered
  #     filter — redirect to that filter's URL, so the address bar reflects it
  #     rather than showing a bare /events that's secretly filtered.
  #   • Plain visit with nothing remembered — render the unfiltered feed.
  #
  # Every branch terminates: a strip/replay redirect lands on a URL that carries
  # the filter as q/g/l/d (or none), so the follow-up request is explicit-without-
  # marker (or truly empty) and renders without redirecting again.
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

  # A deliberate filter action: the form's `filtered` marker (set even when cleared
  # to empty) or an explicit q/g/l/d link. Distinguishes "cleared the filter" from
  # "just landed here", which otherwise look identical (both bare /events).
  def explicit_filter_request?
    params[:filtered].present? || FILTER_KEYS.any? { |key| params[key].present? }
  end

  # Mirror the URL's filter into the cookie: store it when present, delete it on a
  # clear so "clear" actually sticks instead of being replayed on the next visit.
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

  # The remembered filter as a string-keyed params hash (q/g/l/d → arrays), or nil
  # if absent/unreadable. Used to replay it into the URL on a plain visit.
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

  # Use callbacks to share common setup or constraints between actions.
  def set_event
    @event = Event.find(params.expect(:id))
  end
end
