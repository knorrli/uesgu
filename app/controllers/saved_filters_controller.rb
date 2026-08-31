class SavedFiltersController < ApplicationController
  before_action :set_rule, only: %i[edit update destroy fire]

  def index
    @rules = current_user.saved_filters.order(:created_at)
  end

  def new
    @rule = current_user.saved_filters.new(default_schedule)
    @rule.filter_attributes = filter_params
    @filter = filter_for(@rule)
  end

  def create
    @rule = current_user.saved_filters.new(default_schedule)
    @rule.assign_attributes(rule_params) if params[:saved_filter].present?
    @rule.filter_attributes = filter_params

    if (existing = current_user.saved_filters.matching(@rule.fingerprint))
      redirect_to edit_saved_filter_path(existing), notice: t("saved_filters.already_exists")
    elsif @rule.save
      redirect_to saved_filters_path, notice: t("saved_filters.saved")
    else
      @filter = filter_for(@rule)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @filter = filter_for(@rule)
    @duplicate_of = duplicate_of(@rule)
  end

  def update
    @rule.assign_attributes(rule_params) if params[:saved_filter].present?
    @rule.filter_attributes = filter_params

    if @rule.save
      redirect_to saved_filters_path, notice: t("saved_filters.saved")
    else
      @filter = filter_for(@rule)
      @duplicate_of = duplicate_of(@rule)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rule.destroy
    redirect_to saved_filters_path, notice: t("saved_filters.deleted")
  end

  def fire
    notification = @rule.fire!(Time.current)
    if notification
      redirect_to notification_path(notification), notice: t("saved_filters.fired", count: notification.events.size)
    else
      redirect_to saved_filters_path, notice: t("saved_filters.fired_empty")
    end
  end

  private

  def set_rule
    @rule = current_user.saved_filters.find(params[:id])
  end

  def default_schedule
    { cadence: "daily", time_of_day: 1080, weekday: 5, monthday: 1, notify_push: false, notify_email: false }
  end

  def rule_params
    params.require(:saved_filter).permit(
      :name, :cadence, :weekday, :monthday, :time_string, :time_hour, :time_minute,
      :notify_in_app, :notify_push, :notify_email, :highlight_in_feed
    )
  end

  def filter_params
    params.permit(q: [], g: [], l: [], d: []).to_h.symbolize_keys
  end

  def filter_for(rule)
    Filter.build(queries: rule.queries, genres: rule.genres,
                 location_list: rule.location_list, date_ranges: rule.date_ranges)
  end

  def duplicate_of(rule)
    current_user.saved_filters.where.not(id: rule.id).matching(rule.fingerprint)
  end
end
