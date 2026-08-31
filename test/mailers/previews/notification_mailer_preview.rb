class NotificationMailerPreview < ActionMailer::Preview
  def digest
    user = User.first || User.new(username: "preview", locale: "de")
    events = Event.visible.where("start_date >= ?", Date.current).order(start_date: :asc).limit(6)
    events = Event.visible.order(start_date: :desc).limit(6) if events.empty?

    notification = Notification.new(
      user: user,
      title: "Wochen-Digest · Deine Favoriten",
      event_ids: events.map(&:id),
      period_start: 1.week.ago,
      period_end: Time.current
    )
    notification.id = 0

    NotificationMailer.digest(notification)
  end
end
