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
    @filter = filter_for(@rule)
    @matches_favorites = current_user.favorites_filter?(@filter)
  end

  # "Benachrichtigen" creates the rule immediately (it's only offered with an
  # active filter, so it always targets something) and lands on the live editor —
  # there's no draft step. Push/e-mail start OFF (in-app bell only, see
  # default_schedule), so an abandoned rule does nothing intrusive; the user opts
  # those channels in deliberately. Schedule params only arrive from the rare
  # direct-to-/new flow.
  def create
    @rule = current_user.notification_rules.new(default_schedule)
    @rule.assign_attributes(rule_params) if params[:notification_rule].present?
    @rule.filter_attributes = filter_params

    # One alert per filter set: if the user already has a rule for exactly this
    # filter, land them on it (to tweak the schedule/channels) rather than making
    # a duplicate. The events-page bell is already lit in this case.
    if (existing = current_user.notification_rules.matching(@rule.fingerprint))
      redirect_to edit_notification_rule_path(existing), notice: t("notification_rules.already_exists")
    elsif @rule.save
      redirect_to edit_notification_rule_path(@rule)
    else
      redirect_to events_path, alert: @rule.errors.full_messages.to_sentence
    end
  end

  # The whole rule (schedule, channels, name, and the filter via inline
  # multiselect comboboxes + a window select) is edited on this one form. It
  # autosaves: every change submits and the form re-renders inside its turbo
  # frame, so there's no Save button. See #update.
  def edit
    @filter = filter_for(@rule)
    @matches_favorites = current_user.favorites_filter?(@filter)
    @duplicate_of = duplicate_of(@rule)
  end

  # Autosave target: re-render the editor frame with the canonical server state
  # (chips sorted + deduped, dropdowns excluding picks, window as a tag, derived
  # name refreshed) instead of redirecting. Stays put — the user is still editing.
  def update
    @rule.assign_attributes(rule_params) if params[:notification_rule].present?
    @rule.filter_attributes = filter_params
    @rule.save

    @filter = filter_for(@rule)
    @matches_favorites = current_user.favorites_filter?(@filter)
    # Editing CAN knowingly produce two rules for the same filter (the bell can't);
    # surface it as a non-blocking heads-up, never a block. Blocking would trap the
    # autosave editor: trimming "Rock·Metal·Jazz" down to "Rock" passes through
    # "Rock·Metal", which might momentarily collide with another rule.
    @duplicate_of = duplicate_of(@rule) if @rule.persisted?
    render :edit, status: (@rule.errors.any? ? :unprocessable_entity : :ok)
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

  # A new rule starts on the in-app bell only — push and e-mail are opt-in, so a
  # rule created by clicking "Benachrichtigen" (and maybe abandoned) never sends
  # anything intrusive until the user turns those channels on.
  def default_schedule
    { cadence: "daily", time_of_day: 1080, weekday: 5, monthday: 1, notify_push: false, notify_email: false }
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

  # The filter shown on the edit form, built from the rule's saved filter.
  def filter_for(rule)
    Filter.build(queries: rule.queries, location_list: rule.location_list,
                 style_list: rule.style_list, date_ranges: rule.date_ranges)
  end

  # Another of the user's rules with the same filter as `rule`, if any — the
  # editor's non-blocking "you also have a rule for this" heads-up.
  def duplicate_of(rule)
    current_user.notification_rules.where.not(id: rule.id).matching(rule.fingerprint)
  end
end
