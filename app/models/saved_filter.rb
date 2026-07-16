# A saved landing-page filter, with notification delivery OPTIONAL. The user
# builds a filter on the main page ("Rock · Bern · this weekend") and saves it; in
# the editor they can also turn on notifications (in-app is the master channel,
# plus push/email) and a schedule. With notifications off it's a silent saved
# scope. There's no separate builder vocabulary — it's the same filter.
#
# When notifying, whether it's a "newly added" or a "what's happening" digest is
# INFERRED, not chosen:
#   - filter has a relative date window (this_weekend, next_week, ...) → HAPPENING:
#     events occurring in that window, re-resolved each time it fires.
#   - filter has no date window → ADDED: events newly added (by created_at) since
#     it last fired, future-dated only.
#
# The filter (queries/genres/location_list/date_ranges) is frozen at save time and
# matched exactly like the landing page (Filter#ransack_query).
class SavedFilter < ApplicationRecord
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

  # Notifying = the in-app digest is created (notify_in_app on). It's the master
  # channel: push/email require it (see silence_other_channels), so this scope is
  # also "anything that can fire". A saved filter with it off is a silent scope.
  scope :notifying, -> { where(notify_in_app: true) }

  validates :cadence, inclusion: { in: CADENCES }
  validates :time_of_day, numericality: { in: 0..1439 }
  validates :weekday, inclusion: { in: 0..6 }, if: -> { cadence.in?(%w[weekly biweekly]) }
  validates :monthday, inclusion: { in: 1..28 }, if: -> { cadence == "monthly" }
  # An empty filter is allowed on purpose: it's the "notify me about *every* new
  # event" rule. With no criteria the matcher (Filter#ransack_query) resolves to
  # "every visible event from today on", and describe() names it "Alle Events".
  # One saved filter per fingerprint: the save-from-events flow lands on the
  # existing filter instead of cloning (see SavedFiltersController#create),
  # and this enforces it on both create and edit. Duplicate fingerprints would
  # break the events-page "saved?" derivation (matching() returns an arbitrary
  # one), so editing a filter's scope to collide with another is rejected. It
  # excludes self by id, so a schedule/channel-only edit never trips it.
  validate :no_duplicate_filter, on: %i[create update]
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
  # In-app is the master channel: with it off the saved filter is a silent scope,
  # so push/email can't ride on a digest that never fires — force them off. Mirrors
  # the editor's client-side disable (notify-channels controller).
  before_validation :silence_other_channels

  def no_duplicate_filter
    return unless user
    return unless user.saved_filters.where.not(id: id).any? { |rule| rule.fingerprint == fingerprint }

    errors.add(:base, I18n.t("saved_filters.errors.duplicate"))
  end

  before_create { self.last_fired_at ||= Time.current }

  # Fire every notifying rule that's due as of `now` — the per-user-due sweep the
  # scheduler (Render cron, ~every 15 min) calls. Returns the Notifications
  # created (empty digests fire nothing and are dropped).
  def self.run_due!(now = Time.current)
    notifying.includes(:user).find_each.filter_map do |rule|
      rule.fire!(now) if rule.due?(now)
    end
  end

  # ── Filter (mirrors the landing-page params q/l/s/d) ───────────────────────

  def filter_attributes=(params)
    self.filter = {
      "queries" => clean(params[:q]),
      # genres (g[]) is the tree-aware slot the events page + editor feed: each
      # picked genre matches itself + every descendant (see Filter#expanded_genre_names).
      "genres" => clean(params[:g]),
      "location_list" => clean(params[:l]),
      # Rules only do relative windows (re-resolved each fire); a fixed absolute
      # range makes no sense for a recurring alert (and would silently die once
      # past), so drop non-presets — the rule falls back to "new events". And a
      # rule takes exactly ONE window (the cadence derives from it, and the
      # editor's When picker is single-select), so keep only the first — a filter
      # carried over from the feed (where When is multi-select) is narrowed here.
      "date_ranges" => clean(params[:d]).select { |range| Datepicker.preset.key?(range) }.first(1)
    }
  end

  def queries       = Array(filter["queries"])
  def genres        = Array(filter["genres"])
  def location_list = Array(filter["location_list"])
  def date_ranges   = Array(filter["date_ranges"])

  # Relative presets in the saved date filter (this_weekend, next_week, ...).
  # Their presence flips the rule from "added" to "happening".
  def active_windows
    date_ranges.select { |range| Datepicker.preset.key?(range) }
  end

  def happening? = active_windows.any?
  def added? = !happening?

  # ── Identity (dedupe) ──────────────────────────────────────────────────────

  # An order-independent fingerprint of a filter set: the lists as sets (so
  # "Rock · Bern" == "Bern · Rock"), date ranges narrowed to the presets a rule
  # keeps. Two rules with the same fingerprint are the same saved filter — the
  # basis for "you already have this" both at save (no duplicate is made) and on
  # the events page (the ★ lights up).
  def self.fingerprint(queries:, location_list:, date_ranges:, genres: [])
    {
      queries: Set.new(Array(queries).map { |q| q.to_s.strip }.reject(&:blank?)),
      genres: Set.new(Array(genres)),
      location_list: Set.new(Array(location_list)),
      date_ranges: Set.new(Array(date_ranges).select { |range| Datepicker.preset.key?(range) })
    }
  end

  # Fingerprint for a landing-page Filter, so the events controller can ask "is
  # there a saved filter for this exact filter?".
  def self.fingerprint_for(filter)
    fingerprint(queries: filter.queries, genres: filter.genres,
                location_list: filter.location_list, date_ranges: filter.date_ranges)
  end

  def fingerprint
    self.class.fingerprint(queries: queries, genres: genres,
                           location_list: location_list, date_ranges: date_ranges)
  end

  # The rule in this scope whose filter matches `fingerprint`, or nil. Set-based,
  # so it runs in Ruby — fine over a single user's handful of rules. Used as
  # current_user.saved_filters.matching(fp).
  def self.matching(fingerprint)
    all.detect { |rule| rule.fingerprint == fingerprint }
  end

  # The cadence implied by the (first) window — nil for an "added" rule. The form
  # uses this to show the right firing-point control (weekday / day-of-month / —).
  def window_rhythm
    WINDOW_RHYTHM[active_windows.first]
  end

  # ── Scheduling ─────────────────────────────────────────────────────────────

  # Whether this saved filter actually delivers (vs. a silent saved scope). In-app
  # is the master, so notifying? == notify_in_app? — the single notify state.
  def notifying? = notify_in_app?

  def due?(now = Time.current)
    return false unless notify_in_app?
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

  # Events this saved filter covers as of `now`: the exact landing-page query
  # (Filter#ransack_query, which also supplies the future floor when there's no
  # date window). "added" additionally bounds by created_at since the last fire.
  def matched_events(now = Time.current)
    rel = Event.visible
    rel = rel.where(created_at: coverage_floor...now) if added?
    rel.ransack(to_filter.ransack_query).result(distinct: true).order(:start_date, :start_time, :title)
  end

  # ── Firing ─────────────────────────────────────────────────────────────────

  def fire!(now = Time.current)
    events = matched_events(now).to_a
    notification =
      if events.any?
        note = user.notifications.create!(
          saved_filter: self,
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

  # Human "what this saved filter is about" — the auto-name (there are no custom
  # names), the title snapshotted onto each fired notification, and the summary in
  # the Saved filters list.
  # Fixed template: <what> · [<where> ·] <window | "new events">. "what" is the
  # genres + free-text queries, or "Alle Events" when none; the last part is the
  # time window for a happening filter, else the new-events label.
  def describe
    what = (genres + queries).join(", ")
    parts = [what.presence || I18n.t("saved_filters.summary.scope_all")]
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

  # The rule form edits the time as two selects — hour (00–23) and quarter-minute
  # (00/15/30/45) — instead of a native time input, so it reads identically on every
  # device and only the values the scheduler honours are offered (no silent clamp).
  # Each select posts its part; we fold the pair into time_of_day once both arrive
  # (Rails assigns them together from params). time_string stays the single-string
  # view used by the summary helper + tests.
  def time_hour = format("%02d", time_of_day / 60)

  def time_minute = format("%02d", time_of_day % 60)

  def time_hour=(value)
    @time_hour = value
    combine_time_parts
  end

  def time_minute=(value)
    @time_minute = value
    combine_time_parts
  end

  private

  def combine_time_parts
    return if @time_hour.blank? || @time_minute.blank?
    self.time_of_day = (@time_hour.to_i * 60) + @time_minute.to_i
  end

  def clean(value) = Array(value).map { |v| v.to_s.strip }.reject(&:blank?)

  def silence_other_channels
    return if notify_in_app?
    self.notify_push = false
    self.notify_email = false
  end

  def snap_time_to_quarter
    return if time_of_day.blank?
    snapped = (time_of_day / 15.0).round * 15
    snapped -= 15 if snapped >= 1440 # keep a late time on the same day (→ 23:45)
    self.time_of_day = snapped
  end

  # The trailing part of the name: the window label (happening) or the new-events
  # label (added) — always present, so every name reads the same way.
  def temporal_label
    happening? ? window_labels.join(", ") : I18n.t("saved_filters.type.added")
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

  # Builds the same Filter the landing page uses, from the frozen params — so a
  # saved custom filter matches identically (AND across what/where, date presets
  # re-resolved, future floor when no date).
  def to_filter
    # date_ranges = active_windows (presets only) — never a stored absolute range
    # (see filter_attributes=). active_windows also covers any legacy rule that
    # still has one stored, so it falls back to the new-events floor rather than a
    # dead past range.
    Filter.build(queries: queries, genres: genres,
                 location_list: location_list, date_ranges: active_windows)
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
    Rails.logger.error("[saved_filters] email delivery failed for rule ##{id}: #{e.class} #{e.message}")
  end
end
