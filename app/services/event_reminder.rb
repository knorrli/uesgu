# A daily nudge about the shows a user has saved. Unlike a NotificationRule
# (a saved filter + schedule), this is a single global opt-in: once a day, around
# the user's chosen time (noon by default), if any saved show falls on the target
# day (day-of by default), send one digest.
#
# It fires at a fixed wall-clock time, so an event whose start time the scraper
# couldn't read (stored as nil / midnight) is no problem — the nudge doesn't
# depend on the show's own time.
#
# Reuses the notification stack: it creates a Notification (so it lands in the
# inbox) and delivers over whatever channels the user has — push to their
# devices, email if they've added an address.
class EventReminder
  DEFAULT_TIME = 12 * 60 # noon, minutes since midnight

  # Sweep every reminder-enabled user, firing those past their time today that
  # haven't fired yet. Idempotent via last_reminded_on, so the quarter-hourly
  # cron can re-run safely. Returns the Notifications created.
  def self.run_due!(now = Time.current)
    User.where(event_reminders: true).find_each.filter_map do |user|
      new(user, now).fire_if_due!
    end
  end

  def initialize(user, now = Time.current)
    @user = user
    @now = now
  end

  def due?
    return false unless @user.event_reminders?
    return false if @user.last_reminded_on && @user.last_reminded_on >= @now.to_date

    @now >= scheduled_at(@now.to_date)
  end

  # Fire if due, then mark today done either way (we evaluated today; the nudge is
  # a once-a-day digest, not a running watch). Returns the Notification, or nil
  # when nothing was due / nothing matched.
  def fire_if_due!
    return unless due?

    events = target_events.to_a
    notification = deliver(events) if events.any?
    @user.update_column(:last_reminded_on, @now.to_date)
    notification
  end

  # Saved shows on the target day, excluding cancelled/dismissed ones (no point
  # reminding about a show that's off). Public for the controller's "preview".
  def target_events
    @user.saved_events
         .where(start_date: target_date, cancelled_at: nil, dismissed_at: nil)
         .includes(:locations, :genres)
         .order(:start_time, :title)
  end

  def target_date
    @now.to_date + @user.reminder_lead_days
  end

  private

  def scheduled_at(date)
    minutes = @user.reminder_time || DEFAULT_TIME
    Time.zone.local(date.year, date.month, date.day) + minutes.minutes
  end

  def deliver(events)
    I18n.with_locale(locale) do
      note = @user.notifications.create!(
        title: I18n.t('event_reminder.title', count: events.size),
        event_ids: events.map(&:id),
        period_start: target_date.beginning_of_day,
        period_end: target_date.end_of_day
      )
      deliver_push(note, events)
      deliver_email(note)
      note
    end
  end

  def deliver_push(note, events)
    return unless WebPushConfig.configured?
    return if @user.push_subscriptions.none?

    title = I18n.t('push.digest.title')
    body = I18n.t('event_reminder.push_body', count: events.size)
    path = Rails.application.routes.url_helpers.notification_path(note)
    @user.push_subscriptions.find_each { |sub| sub.deliver(title: title, body: body, path: path) }
  end

  # Isolated so a bad address / SMTP hiccup can't abort the firing (or the sweep).
  def deliver_email(note)
    return unless MailConfig.configured? && @user.email_address.present?

    NotificationMailer.digest(note).deliver_later
  rescue StandardError => e
    Rails.logger.error("[event_reminder] email delivery failed for user ##{@user.id}: #{e.class} #{e.message}")
  end

  def locale
    @user.locale.presence || I18n.default_locale
  end
end
