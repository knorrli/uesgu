# A saved landing-page filter + a schedule. The user builds a filter on the main
# page ("Rock · Bern · this weekend") and attaches a cadence/time/channel to it —
# there's no separate builder vocabulary.
#
# Whether it's a "what's newly added" or a "what's happening" digest is INFERRED,
# not chosen:
#   - filter has a relative date window (this_weekend, next_week, ...) → HAPPENING:
#     events occurring in that window, re-resolved each time it fires.
#   - filter has no date window → ADDED: events newly added (by created_at) since
#     the rule last fired, future-dated only.
#
# The filter (queries/style_list/location_list/date_ranges) is frozen at save
# time and matched exactly like the landing page (Filter#ransack_query). The one
# exception is track_favorites: a favorites alert stays live, re-resolving the
# user's followed locations/styles (OR-matched) at send time.
class NotificationRule < ApplicationRecord
  CADENCES = %w[daily weekly biweekly monthly].freeze

  # For a "happening" rule the firing cadence is DERIVED from the window's period
  # (a weekend/week window fires weekly, a month window monthly, today/tomorrow
  # daily) — so cadence and window can never clash. "added" rules pick cadence
  # freely; biweekly therefore only ever applies to "added" rules.
  WINDOW_RHYTHM = {
    "today" => "daily", "tomorrow" => "daily",
    "this_week" => "weekly", "this_weekend" => "weekly",
    "next_week" => "weekly", "next_weekend" => "weekly",
    "this_month" => "monthly", "next_month" => "monthly"
  }.freeze

  belongs_to :user
  has_many :notifications, dependent: :nullify

  scope :enabled, -> { where(enabled: true) }

  validates :cadence, inclusion: { in: CADENCES }
  validates :time_of_day, numericality: { in: 0..1439 }
  validates :weekday, inclusion: { in: 0..6 }, if: -> { cadence.in?(%w[weekly biweekly]) }
  validates :monthday, inclusion: { in: 1..28 }, if: -> { cadence == "monthly" }
  # No unconstrained firehose: a rule must target *something* — some filter, or
  # the live-favorites flag. (The "Notify me" button is also hidden on an empty
  # filter; this is the backstop.)
  validate :targets_something
  validates :name, presence: true

  # The name always mirrors the filter — there are no custom names. Re-derived on
  # every save so it tracks edits; the form shows it as a live, read-only preview.
  before_validation { self.name = describe }
  # A happening rule's cadence is fixed by its window (see WINDOW_RHYTHM), so the
  # form hides the cadence control and the user can't pick a clashing cadence.
  before_validation { self.cadence = window_rhythm if happening? }
  # The scheduler sweeps quarter-hourly, so a rule only ever fires at
  # :00/:15/:30/:45 — snap the chosen time to the nearest quarter so the saved
  # time matches when it actually fires (the form's input also steps by 15 min).
  before_validation :snap_time_to_quarter

  def targets_something
    return if track_favorites?
    return if queries.any? || style_list.any? || location_list.any? || date_ranges.any?

    errors.add(:base, I18n.t("notification_rules.errors.empty_filter"))
  end

  before_create { self.last_fired_at ||= Time.current }

  # Fire every enabled rule that's due as of `now` — the per-user-due sweep the
  # scheduler (Render cron, ~every 15 min) calls. Returns the Notifications
  # created (empty digests fire nothing and are dropped).
  def self.run_due!(now = Time.current)
    enabled.includes(:user).find_each.filter_map do |rule|
      rule.fire!(now) if rule.due?(now)
    end
  end

  # ── Filter (mirrors the landing-page params q/l/s/d) ───────────────────────

  def filter_attributes=(params)
    self.filter = {
      "queries" => clean(params[:q]),
      "style_list" => clean(params[:s]),
      "location_list" => clean(params[:l]),
      # Rules only do relative windows (re-resolved each fire); a fixed absolute
      # range makes no sense for a recurring alert (and would silently die once
      # past), so drop non-presets — the rule falls back to "new events".
      "date_ranges" => clean(params[:d]).select { |range| Datepicker.preset.key?(range) }
    }
  end

  def queries       = Array(filter["queries"])
  def style_list    = Array(filter["style_list"])
  def location_list = Array(filter["location_list"])
  def date_ranges   = Array(filter["date_ranges"])

  # Relative presets in the saved date filter (this_weekend, next_week, ...).
  # Their presence flips the rule from "added" to "happening".
  def active_windows
    date_ranges.select { |range| Datepicker.preset.key?(range) }
  end

  def happening? = active_windows.any?
  def added? = !happening?

  # The cadence implied by the (first) window — nil for an "added" rule. The form
  # uses this to show the right firing-point control (weekday / day-of-month / —).
  def window_rhythm
    WINDOW_RHYTHM[active_windows.first]
  end

  # ── Scheduling ─────────────────────────────────────────────────────────────

  def due?(now = Time.current)
    return false unless enabled?
    moment = previous_scheduled_at(now)
    moment.present? && (last_fired_at.nil? || last_fired_at < moment)
  end

  # The most recent moment this rule was supposed to fire, at or before `now`,
  # in the app timezone (Europe/Berlin == Swiss wall-clock, DST-aware).
  def previous_scheduled_at(now = Time.current)
    case cadence
    when "daily"
      today = at_time(now.to_date)
      today <= now ? today : at_time(now.to_date - 1)
    when "weekly", "biweekly"
      diff = (now.to_date.wday - weekday.to_i) % 7
      candidate = at_time(now.to_date - diff)
      candidate -= 7.days if candidate > now
      candidate -= 7.days if biweekly? && off_parity?(candidate)
      candidate
    when "monthly"
      day = [(monthday || 1), 28].min
      candidate = at_time(Date.new(now.year, now.month, day))
      candidate -= 1.month if candidate > now
      candidate
    end
  end

  # ── Matching ───────────────────────────────────────────────────────────────

  # Events this rule covers as of `now`. Non-favorites reuse the exact landing-
  # page query (Filter#ransack_query, which also supplies the future floor when
  # there's no date window); favorites get the live OR-match. "added" additionally
  # bounds by created_at since the last fire.
  def matched_events(now = Time.current)
    # A live-favorites rule whose user has unfollowed everything must match
    # nothing, not every event (no favorites → no OR group → would be a firehose).
    return Event.none if track_favorites? && user.location_list.empty? && user.style_list.empty?

    rel = Event.visible
    rel = rel.where(created_at: coverage_floor...now) if added?
    rel.ransack(ransack_query(now)).result(distinct: true).order(:start_date, :start_time, :title)
  end

  # ── Firing ─────────────────────────────────────────────────────────────────

  def fire!(now = Time.current)
    events = matched_events(now).to_a
    notification =
      if events.any?
        note = user.notifications.create!(
          notification_rule: self,
          title: display_name,
          event_ids: events.map(&:id),
          period_start: coverage_start(now),
          period_end: coverage_end(now)
        )
        deliver(note, events)
        note
      end
    update_column(:last_fired_at, now)
    notification
  end

  def display_name
    name.presence || describe
  end

  # Human "what this alert is about" — the auto-name when the user didn't set
  # one, the title snapshotted onto each fired notification, and the summary in
  # the alerts list.
  # Fixed template: <what> · [<where> ·] <window | "new events">. "what" is the
  # styles + free-text queries, or "Alle Events" when none; the last part is the
  # time window for a happening rule, else the new-events label. The editor
  # autosaves, so the title re-renders from this on every change (server-side, no
  # client mirror).
  def describe
    return describe_favorites if track_favorites?

    what = (style_list + queries).join(", ")
    parts = [what.presence || I18n.t("notification_rules.summary.scope_all")]
    parts << location_list.join(", ") if location_list.any?
    parts << temporal_label
    parts.join(" · ")
  end

  def time_string
    format("%02d:%02d", time_of_day / 60, time_of_day % 60)
  end

  def time_string=(value)
    return if value.blank?
    hours, minutes = value.to_s.split(":").map(&:to_i)
    self.time_of_day = (hours * 60) + minutes.to_i
  end

  private

  def clean(value) = Array(value).map { |v| v.to_s.strip }.reject(&:blank?)

  def snap_time_to_quarter
    return if time_of_day.blank?
    snapped = (time_of_day / 15.0).round * 15
    snapped -= 15 if snapped >= 1440 # keep a late time on the same day (→ 23:45)
    self.time_of_day = snapped
  end

  def describe_favorites
    "#{I18n.t('notification_rules.favorites_live')} · #{temporal_label}"
  end

  # The trailing part of the name: the window label (happening) or the new-events
  # label (added) — always present, so every name reads the same way.
  def temporal_label
    happening? ? window_labels.join(", ") : I18n.t("notification_rules.type.added")
  end

  def window_labels
    active_windows.map { |w| I18n.t("datepicker.#{w}") }
  end

  def biweekly? = cadence == "biweekly"

  def off_parity?(candidate)
    ((candidate.to_date - created_at.to_date).to_i / 7).odd?
  end

  def at_time(date)
    # Construct the wall-clock time directly rather than adding minutes to local
    # midnight: on a DST-transition day the latter double-counts the skipped/
    # repeated hour (a daily 18:00 rule drifted to 19:00 on the spring-forward day).
    Time.zone.local(date.year, date.month, date.day, time_of_day / 60, time_of_day % 60)
  end

  def coverage_floor = last_fired_at || created_at || Time.current

  def coverage_start(now)
    happening? ? window_bounds.first.beginning_of_day : coverage_floor
  end

  def coverage_end(now)
    happening? ? window_bounds.last.end_of_day : now
  end

  def window_bounds
    values = active_windows.map { |w| Datepicker.preset[w][:values] }
    starts = values.map { |s, _| Date.iso8601(s) }
    ends   = values.map { |_, e| Date.iso8601(e) }
    [starts.min, ends.max]
  end

  def ransack_query(now)
    if track_favorites?
      groups = []
      locations = user.location_list
      styles = user.style_list
      if locations.any? || styles.any?
        groups << { locations_name_in: locations.presence, styles_name_in: styles.presence, m: "or" }
      end
      groups << favorites_date_group(now)
      { g: groups }
    else
      to_filter.ransack_query
    end
  end

  # Builds the same Filter the landing page uses, from the frozen params — so a
  # saved custom filter matches identically (AND across what/where, date presets
  # re-resolved, future floor when no date).
  def to_filter
    # date_ranges = active_windows (presets only) — never a stored absolute range
    # (see filter_attributes=). active_windows also covers any legacy rule that
    # still has one stored, so it falls back to the new-events floor rather than a
    # dead past range.
    Filter.build(queries: queries, style_list: style_list,
                 location_list: location_list, date_ranges: active_windows)
  end

  # Date constraint for the favorites path (which can't reuse Filter — it needs
  # OR across location/style). Mirrors Filter's date handling.
  def favorites_date_group(now)
    if active_windows.any?
      ranges = active_windows.map { |w| s, e = Datepicker.preset[w][:values]; "#{s} - #{e}" }
      { start_date_between_any: ranges }
    else
      { start_date_gteq: now.beginning_of_day }
    end
  end

  def deliver(notification, events)
    NotificationPush.deliver(self, notification, events) if notify_push?
    deliver_email(notification) if notify_email? && MailConfig.configured? && user.email_address.present?
  end

  # Isolated so a bad address / SMTP hiccup can't abort the firing (or, in the
  # sweep, the rest of the run) — the in-app digest and push already landed.
  def deliver_email(notification)
    NotificationMailer.digest(notification).deliver_later
  rescue StandardError => e
    Rails.logger.error("[notification_rules] email delivery failed for rule ##{id}: #{e.class} #{e.message}")
  end
end
