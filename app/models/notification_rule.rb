# A user-defined notification "funnel": WHEN to fire · WHICH events · WHICH
# filter · on WHICH channels. One user can have several. Every firing writes a
# Notification (the in-app inbox + unread badge); push and/or email ride on top
# per rule.
#
# The two content types are the heart of it:
#   - "added"     → events newly added to the site since this rule last fired
#                   (by created_at). The discovery/"just posted" case.
#   - "happening" → events taking place in a window like "this weekend" or
#                   "next week" (by start_date), regardless of when they were
#                   added. The going-out/"what's on" case. The window reuses the
#                   same Datepicker presets as the main filter.
class NotificationRule < ApplicationRecord
  CADENCES = %w[daily weekly biweekly monthly].freeze
  CONTENT_TYPES = %w[added happening].freeze
  SCOPES = %w[all favorites custom].freeze
  # The Datepicker presets that make sense as a "happening" window.
  WINDOWS = %w[today tomorrow this_week this_weekend next_week next_weekend this_month next_month].freeze

  belongs_to :user
  has_many :notifications, dependent: :nullify

  scope :enabled, -> { where(enabled: true) }

  validates :cadence, inclusion: { in: CADENCES }
  validates :content_type, inclusion: { in: CONTENT_TYPES }
  validates :scope, inclusion: { in: SCOPES }
  validates :time_of_day, numericality: { in: 0..1439 }
  validates :weekday, inclusion: { in: 0..6 }, if: -> { cadence.in?(%w[weekly biweekly]) }
  validates :monthday, inclusion: { in: 1..28 }, if: -> { cadence == "monthly" }
  validates :window, inclusion: { in: WINDOWS }, if: :happening?

  # New rules start "caught up" so the first fire covers events from creation
  # onward, never a backlog blast from the dawn of the account.
  before_create { self.last_fired_at ||= Time.current }

  # Fire every enabled rule that's due as of `now`. This is the per-user-due
  # sweep the scheduler (Render cron, ~every 15 min) calls. Returns the
  # Notifications created (empty digests fire nothing and are dropped).
  def self.run_due!(now = Time.current)
    enabled.includes(:user).find_each.filter_map do |rule|
      rule.fire!(now) if rule.due?(now)
    end
  end

  def added? = content_type == "added"
  def happening? = content_type == "happening"
  def favorites? = scope == "favorites"
  def custom? = scope == "custom"

  # ── Scheduling ────────────────────────────────────────────────────────────

  # Due when the most recent scheduled wall-clock moment has passed and we
  # haven't already fired for it. Same gate for both content types.
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
      at_time(now.to_date, now) { |t| t <= now ? t : at_time(now.to_date - 1, now) }
    when "weekly", "biweekly"
      diff = (now.to_date.wday - weekday.to_i) % 7
      candidate = at_time(now.to_date - diff, now)
      candidate -= 7.days if candidate > now
      candidate -= 7.days if biweekly? && weeks_off_parity?(candidate)
      candidate
    when "monthly"
      day = [(monthday || 1), 28].min
      candidate = at_time(Date.new(now.year, now.month, day), now)
      candidate -= 1.month if candidate > now
      candidate
    end
  end

  # ── Matching ──────────────────────────────────────────────────────────────

  # The events this rule covers as of `now`: the filter (all/favorites/custom)
  # intersected with either the "added since last fire" window or the
  # "happening in this preset" window.
  def matched_events(now = Time.current)
    rel = Event.visible
    rel = rel.where(created_at: coverage_floor...now) if added?
    rel.ransack(g: ransack_groups(now)).result(distinct: true)
       .order(:start_date, :start_time, :title)
  end

  # ── Firing ────────────────────────────────────────────────────────────────

  # Build a digest, deliver it on the enabled channels, advance the cursor.
  # Returns the created Notification, or nil when there was nothing to send.
  # Empty digests are skipped on both types — we never buzz "0 events".
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

  # "HH:MM" accessors so a native <input type="time"> binds straight to the
  # minutes-since-midnight column.
  def time_string
    format("%02d:%02d", time_of_day / 60, time_of_day % 60)
  end

  def time_string=(value)
    return if value.blank?
    hours, minutes = value.to_s.split(":").map(&:to_i)
    self.time_of_day = (hours * 60) + minutes.to_i
  end

  private

  def biweekly? = cadence == "biweekly"

  # Two-week parity anchored to creation, so "every other Friday" stays on the
  # same fortnight it started. (Approximate by design — good enough for a digest.)
  def weeks_off_parity?(candidate)
    ((candidate.to_date - created_at.to_date).to_i / 7).odd?
  end

  # A given date at this rule's time-of-day, in app TZ. Yields to allow the
  # daily "today-or-yesterday" branch to compose cleanly.
  def at_time(date, _now)
    t = Time.zone.local(date.year, date.month, date.day) + time_of_day.minutes
    block_given? ? yield(t) : t
  end

  def coverage_floor = last_fired_at || created_at || Time.current

  def coverage_start(now)
    happening? ? window_range&.first&.to_time : coverage_floor
  end

  def coverage_end(now)
    happening? ? window_range&.last&.end_of_day : now
  end

  def window_range
    preset = Datepicker.preset[window]
    return nil unless preset
    s, e = preset[:values]
    Date.iso8601(s)..Date.iso8601(e)
  end

  def ransack_groups(now)
    groups = []

    case scope
    when "favorites"
      locations = user.location_list
      styles = user.style_list
      if locations.any? || styles.any?
        # Broad/discovery: a favorite location OR a favorite style.
        groups << { locations_name_in: locations.presence, styles_name_in: styles.presence, m: "or" }
      end
    when "custom"
      queries = Array(filter["queries"]).reject(&:blank?)
      groups << { title_or_subtitle_or_styles_name_or_genres_name_cont_any: queries } if queries.any?
      styles = Array(filter["style_list"]).reject(&:blank?)
      groups << { styles_name_in: styles } if styles.any?
      locations = Array(filter["location_list"]).reject(&:blank?)
      groups << { locations_name_in: locations } if locations.any?
    end

    if happening? && (preset = Datepicker.preset[window])
      starts, ends = preset[:values]
      groups << { start_date_gteq: starts, start_date_lteq: ends }
    elsif added?
      # Don't surface a freshly-scraped show that's already in the past. Anchored
      # to the evaluation clock (not Date.current) so it stays consistent with
      # the rest of the window logic.
      groups << { start_date_gteq: now.beginning_of_day }
    end

    groups
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
