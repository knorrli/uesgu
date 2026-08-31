class SavedFilter < ApplicationRecord
  CADENCES = %w[daily weekly biweekly monthly].freeze

  WINDOW_RHYTHM = {
    "today" => "daily", "tomorrow" => "daily",
    "this_week" => "weekly", "this_weekend" => "weekly",
    "next_week" => "weekly", "next_weekend" => "weekly",
    "this_month" => "monthly", "next_month" => "monthly"
  }.freeze

  belongs_to :user
  has_many :notifications, dependent: :nullify

  scope :notifying, -> { where(notify_in_app: true) }

  scope :highlighting, -> { where(highlight_in_feed: true) }

  validates :cadence, inclusion: { in: CADENCES }
  validates :time_of_day, numericality: { in: 0..1439 }
  validates :weekday, inclusion: { in: 0..6 }, if: -> { cadence.in?(%w[weekly biweekly]) }
  validates :monthday, inclusion: { in: 1..28 }, if: -> { cadence == "monthly" }
  validate :no_duplicate_filter, on: %i[create update]
  validates :name, presence: true

  before_validation { self.name = describe }
  before_validation { self.cadence = window_rhythm if happening? }
  before_validation :snap_time_to_quarter
  before_validation :silence_other_channels

  def no_duplicate_filter
    return unless user
    return unless user.saved_filters.where.not(id: id).any? { |rule| rule.fingerprint == fingerprint }

    errors.add(:base, I18n.t("saved_filters.errors.duplicate"))
  end

  before_create { self.last_fired_at ||= Time.current }

  def self.run_due!(now = Time.current)
    notifying.includes(:user).find_each.filter_map do |rule|
      rule.fire!(now) if rule.due?(now)
    end
  end

  def filter_attributes=(params)
    self.filter = {
      "queries" => clean(params[:q]),
      "genres" => clean(params[:g]),
      "location_list" => clean(params[:l]),
      "date_ranges" => clean(params[:d]).select { |range| Datepicker.preset.key?(range) }.first(1)
    }
  end

  def queries       = Array(filter["queries"])
  def genres        = Array(filter["genres"])
  def location_list = Array(filter["location_list"])
  def date_ranges   = Array(filter["date_ranges"])

  def active_windows
    date_ranges.select { |range| Datepicker.preset.key?(range) }
  end

  def happening? = active_windows.any?
  def added? = !happening?

  def self.fingerprint(queries:, location_list:, date_ranges:, genres: [])
    {
      queries: Set.new(Array(queries).map { |q| q.to_s.strip }.reject(&:blank?)),
      genres: Set.new(Array(genres)),
      location_list: Set.new(Array(location_list).map { |name| Fingerprint.for(name) }),
      date_ranges: Set.new(Array(date_ranges).select { |range| Datepicker.preset.key?(range) })
    }
  end

  def self.fingerprint_for(filter)
    fingerprint(queries: filter.queries, genres: filter.genres,
                location_list: filter.location_list, date_ranges: filter.date_ranges)
  end

  def fingerprint
    self.class.fingerprint(queries: queries, genres: genres,
                           location_list: location_list, date_ranges: date_ranges)
  end

  def self.matching(fingerprint)
    all.detect { |rule| rule.fingerprint == fingerprint }
  end

  def window_rhythm
    WINDOW_RHYTHM[active_windows.first]
  end

  def notifying? = notify_in_app?

  def due?(now = Time.current)
    return false unless notify_in_app?
    moment = previous_scheduled_at(now)
    moment.present? && (last_fired_at.nil? || last_fired_at < moment)
  end

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

  def matched_events(now = Time.current)
    rel = Event.visible
    rel = rel.where(created_at: coverage_floor...now) if added?
    rel.ransack(to_filter.ransack_query).result(distinct: true).order(:start_date, :start_time, :title)
  end

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
    snapped -= 15 if snapped >= 1440
    self.time_of_day = snapped
  end

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

  def to_filter
    Filter.build(queries: queries, genres: genres,
                 location_list: location_list, date_ranges: active_windows)
  end

  def deliver(notification, events)
    NotificationPush.deliver(self, notification, events) if notify_push?
    deliver_email(notification) if notify_email? && MailConfig.configured? && user.email_address.present?
  end

  def deliver_email(notification)
    NotificationMailer.digest(notification).deliver_later
  rescue StandardError => e
    Rails.logger.error("[saved_filters] email delivery failed for rule ##{id}: #{e.class} #{e.message}")
  end
end
