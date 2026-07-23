# Notification rules = saved landing-page filters (notification delivery optional).
#
# Saving starts on the events page ★: a not-yet-saved filter links to `new` with
# the current filter params (q/g/l/s/d) pre-loaded as an unsaved draft; `create`
# persists it and returns to the Filter list. An already-saved filter links
# straight to its `edit`. `index` is the Saved-filters list; fire/destroy manage
# individual filters. There's no separate pause switch — a filter delivers iff its
# in-app channel (notify_in_app) is on (see SavedFilter#notifying?).
class SavedFiltersController < ApplicationController
  before_action :set_rule, only: %i[edit update destroy fire]

  def index
    @rules = current_user.saved_filters.order(:created_at)
  end

  # The events-page ★ on a not-yet-saved filter lands here: the editor, with the
  # current filter pre-loaded as an unsaved draft (nothing persisted until Save).
  def new
    @rule = current_user.saved_filters.new(default_schedule)
    @rule.filter_attributes = filter_params
    @filter = filter_for(@rule)
  end

  # Persist the drafted filter and return to the Saved-filters list. In-app starts
  # ON (default_schedule) so a saved filter notifies by default; push/email stay
  # off until opted in. If the exact filter already exists, land on it instead of
  # making a duplicate (the events ★ already routes saved filters to edit; this
  # backstops a draft edited to collide).
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

  # The whole saved filter — its scope (the genre/location tree + window) and its
  # schedule/channels — is edited on one plain form (no autosave). See #update.
  def edit
    @filter = filter_for(@rule)
    @duplicate_of = duplicate_of(@rule)
  end

  # Save the edited filter + schedule and return to the Saved filters list. On a
  # validation error, re-render the editor with the messages.
  def update
    @rule.assign_attributes(rule_params) if params[:saved_filter].present?
    @rule.filter_attributes = filter_params

    if @rule.save
      redirect_to saved_filters_path, notice: t("saved_filters.saved")
    else
      @filter = filter_for(@rule)
      # Re-surface the "another rule already covers this" link alongside the error
      # (the edit page renders it from @duplicate_of).
      @duplicate_of = duplicate_of(@rule)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rule.destroy
    redirect_to saved_filters_path, notice: t("saved_filters.deleted")
  end

  # "Fire now": run the rule immediately on its real channels so you can see the
  # in-app digest (and any push/email) without waiting for the schedule.
  def fire
    notification = @rule.fire!(Time.current)
    if notification
      # Land straight on the digest it produced (created inline, so it's ready).
      redirect_to notification_path(notification), notice: t("saved_filters.fired", count: notification.events.size)
    else
      redirect_to saved_filters_path, notice: t("saved_filters.fired_empty")
    end
  end

  private

  def set_rule
    @rule = current_user.saved_filters.find(params[:id])
  end

  # A new saved filter starts on the in-app channel only — push and e-mail are
  # opt-in, so a filter saved from the events ★ (and maybe never tuned) never sends
  # anything intrusive until the user turns those channels on. notify_in_app
  # defaults on (the DB default) so a saved filter notifies in-app out of the box.
  def default_schedule
    { cadence: "daily", time_of_day: 1080, weekday: 5, monthday: 1, notify_push: false, notify_email: false }
  end

  def rule_params
    params.require(:saved_filter).permit(
      :name, :cadence, :weekday, :monthday, :time_string, :time_hour, :time_minute,
      :notify_in_app, :notify_push, :notify_email, :highlight_in_feed
    )
  end

  # The landing-page filter, carried straight through (same keys as events#index).
  def filter_params
    params.permit(q: [], g: [], l: [], d: []).to_h.symbolize_keys
  end

  # The filter shown on the edit form, built from the rule's saved filter.
  def filter_for(rule)
    Filter.build(queries: rule.queries, genres: rule.genres,
                 location_list: rule.location_list, date_ranges: rule.date_ranges)
  end

  # Another of the user's rules with the same filter as `rule`, if any — the
  # editor's non-blocking "you also have a rule for this" heads-up.
  def duplicate_of(rule)
    current_user.saved_filters.where.not(id: rule.id).matching(rule.fingerprint)
  end
end
