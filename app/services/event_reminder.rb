class EventReminder
  DEFAULT_TIME = 12 * 60

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

  def fire_if_due!
    return unless due?

    events = target_events.to_a
    notification = deliver(events) if events.any?
    @user.update_column(:last_reminded_on, @now.to_date)
    notification
  end

  def target_events
    @user.saved_events
         .merge(Event.visible)
         .where(start_date: target_date, cancelled_at: nil)
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
        title: I18n.t("event_reminder.title", count: events.size),
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

    title = I18n.t("push.digest.title")
    body = I18n.t("event_reminder.push_body", count: events.size)
    path = Rails.application.routes.url_helpers.notification_path(note)
    @user.push_subscriptions.find_each { |sub| sub.deliver(title: title, body: body, path: path) }
  end

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
