# The "list of notification rules" management screen. index renders the user's
# rules plus an inline builder; create/destroy/toggle manage them; fire runs one
# on demand so a rule can be tested without waiting for its schedule.
class NotificationRulesController < ApplicationController
  before_action :set_rule, only: %i[destroy toggle fire]

  def index
    @rules = current_user.notification_rules.order(:created_at)
    @rule = current_user.notification_rules.new(default_attributes)
  end

  def create
    @rule = current_user.notification_rules.new(rule_params)
    if @rule.save
      redirect_to notification_rules_path, notice: t("notification_rules.created")
    else
      @rules = current_user.notification_rules.order(:created_at)
      render :index, status: :unprocessable_entity
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

  # "Fire now": run the rule immediately on the real channels, so you can see the
  # in-app digest (and any push/email) without waiting for the schedule.
  def fire
    notification = @rule.fire!(Time.current)
    notice = if notification
               t("notification_rules.fired", count: notification.events.size)
             else
               t("notification_rules.fired_empty")
             end
    redirect_to notification_rules_path, notice: notice
  end

  private

  def set_rule
    @rule = current_user.notification_rules.find(params[:id])
  end

  def default_attributes
    { cadence: "daily", content_type: "added", scope: "favorites",
      time_of_day: 1080, weekday: 5, monthday: 1, window: "this_weekend",
      notify_push: true, notify_email: false }
  end

  def rule_params
    raw = params.require(:notification_rule).permit(
      :name, :cadence, :weekday, :monthday, :time_string, :content_type, :window,
      :scope, :notify_push, :notify_email, :filter_queries, :filter_styles, :filter_locations
    )

    # Assemble the custom filter from three comma/newline-separated text fields.
    if raw[:scope] == "custom"
      raw[:filter] = {
        "queries" => split_list(raw[:filter_queries]),
        "style_list" => split_list(raw[:filter_styles]),
        "location_list" => split_list(raw[:filter_locations])
      }
    end
    raw.delete(:filter_queries)
    raw.delete(:filter_styles)
    raw.delete(:filter_locations)

    # Null out fields that don't apply to the chosen cadence/content type so a
    # stale hidden value can't fail validation.
    raw[:weekday] = nil unless raw[:cadence].in?(%w[weekly biweekly])
    raw[:monthday] = nil unless raw[:cadence] == "monthly"
    raw[:window] = nil unless raw[:content_type] == "happening"

    raw
  end

  def split_list(value)
    value.to_s.split(/[,\n]/).map(&:strip).reject(&:blank?)
  end
end
