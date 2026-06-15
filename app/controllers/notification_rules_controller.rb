# Notification rules = saved landing-page filters + a schedule.
#
# Creation starts on the events page ("Notify me about this"), which links here
# with the current filter params (q/l/s/d). `new` shows the schedule form with
# that filter pre-loaded; `create` saves it. `index` is the read-only "My alerts"
# list; fire/toggle/destroy manage individual alerts.
class NotificationRulesController < ApplicationController
  before_action :set_rule, only: %i[edit update destroy toggle fire]

  def index
    @rules = current_user.notification_rules.order(:created_at)
  end

  def new
    @rule = current_user.notification_rules.new(default_schedule)
    @rule.filter_attributes = filter_params
    @filter = build_filter           # for the read-only "Notify me about:" chips
    @matches_favorites = favorites_match?(@filter)
  end

  def create
    @rule = current_user.notification_rules.new(rule_params)
    @rule.filter_attributes = filter_params

    if @rule.save
      redirect_to notification_rules_path, notice: t("notification_rules.created")
    else
      @filter = build_filter
      @matches_favorites = favorites_match?(@filter)
      render :new, status: :unprocessable_entity
    end
  end

  # The whole rule (schedule, channels, name, and the filter via inline
  # multiselect comboboxes + a window select) is edited on this one form.
  def edit
    @filter = filter_for(@rule)
    @matches_favorites = favorites_match?(@filter)
  end

  def update
    @rule.assign_attributes(rule_params)
    @rule.filter_attributes = filter_params

    if @rule.save
      redirect_to notification_rules_path, notice: t("notification_rules.updated")
    else
      @filter = filter_for(@rule)
      @matches_favorites = favorites_match?(@filter)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rule.destroy
    redirect_to notification_rules_path, notice: t("notification_rules.deleted")
  end

  def toggle
    @rule.update(enabled: !@rule.enabled)
    redirect_to notification_rules_path
  end

  # "Fire now": run the rule immediately on its real channels so you can see the
  # in-app digest (and any push/email) without waiting for the schedule.
  def fire
    notification = @rule.fire!(Time.current)
    if notification
      # Land straight on the digest it produced (created inline, so it's ready).
      redirect_to notification_path(notification), notice: t("notification_rules.fired", count: notification.events.size)
    else
      redirect_to notification_rules_path, notice: t("notification_rules.fired_empty")
    end
  end

  private

  def set_rule
    @rule = current_user.notification_rules.find(params[:id])
  end

  def default_schedule
    { cadence: "daily", time_of_day: 1080, weekday: 5, monthday: 1, notify_push: true, notify_email: false }
  end

  def rule_params
    params.require(:notification_rule).permit(
      :name, :cadence, :weekday, :monthday, :time_string, :notify_push, :notify_email, :track_favorites
    )
  end

  # The landing-page filter, carried straight through (same keys as events#index).
  def filter_params
    params.permit(q: [], l: [], s: [], d: []).to_h.symbolize_keys
  end

  def build_filter
    Filter.new.tap do |filter|
      filter.queries = params[:q].compact_blank if params[:q].present?
      filter.location_list = params[:l] if params[:l].present?
      filter.style_list = params[:s] if params[:s].present?
      filter.date_ranges = params[:d].compact_blank if params[:d].present?
    end
  end

  # The filter shown on the edit form, built from the rule's saved filter.
  def filter_for(rule)
    Filter.new.tap do |filter|
      filter.queries = rule.queries
      filter.location_list = rule.location_list
      filter.style_list = rule.style_list
      filter.date_ranges = rule.date_ranges
    end
  end

  # True when the filter's tags are exactly the user's favorites (and there's no
  # extra free-text query) — the only case where "keep in sync" is meaningful.
  def favorites_match?(filter)
    return false if filter.queries.any?
    return false unless current_user.location_list.any? || current_user.style_list.any?

    Set.new(filter.location_list) == Set.new(current_user.location_list) &&
      Set.new(filter.style_list) == Set.new(current_user.style_list)
  end
end
