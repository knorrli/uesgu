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
      "date_ranges" => clean(params[:d])
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
    name.presence || I18n.t("notification_rules.default_name", default: "Notification")
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

  def biweekly? = cadence == "biweekly"

  def off_parity?(candidate)
    ((candidate.to_date - created_at.to_date).to_i / 7).odd?
  end

  def at_time(date)
    Time.zone.local(date.year, date.month, date.day) + time_of_day.minutes
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
    Filter.new.tap do |f|
      f.queries = queries
      f.style_list = style_list
      f.location_list = location_list
      f.date_ranges = date_ranges
    end
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
