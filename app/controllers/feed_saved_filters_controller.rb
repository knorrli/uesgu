class FeedSavedFiltersController < ApplicationController
  def create
    adopt_feed_criteria current_user.saved_filters.new(SavedFilter::DEFAULT_SCHEDULE)
  end

  def update
    adopt_feed_criteria current_user.saved_filters.find(params[:id])
  end

  private

  def adopt_feed_criteria(rule)
    rule.filter_attributes = filter_params
    rule = already_saved(rule) || rule.tap(&:save!)

    redirect_to events_path(q: rule.queries, g: rule.genres, l: rule.location_list, d: rule.date_ranges,
                            applied: rule.id, filtered: 1)
  end

  def filter_params
    params.permit(q: [], g: [], l: [], d: []).to_h.symbolize_keys
  end

  def already_saved(rule)
    current_user.saved_filters.where.not(id: rule.id).matching(rule.fingerprint)
  end
end
