# Rule-aware Web Push: a short blurb that deep-links to the in-app notification
# page (the full detail lives there and in the email — push is just the nudge).
# Parallel to WebPushNotifier (the legacy frequency-digest push); both end up in
# PushSubscription#deliver, which prunes dead endpoints.
class NotificationPush
  def self.deliver(rule, notification, events)
    new(rule, notification, events).deliver
  end

  def initialize(rule, notification, events)
    @rule = rule
    @notification = notification
    @events = events
  end

  def deliver
    return unless WebPushConfig.configured?
    user = @rule.user
    return if user.push_subscriptions.none?

    I18n.with_locale(user.locale.presence || I18n.default_locale) do
      title = I18n.t("push.digest.title")
      body = I18n.t("notification_rules.push_body", name: @rule.display_name, count: @events.size)
      path = Rails.application.routes.url_helpers.notification_path(@notification)
      user.push_subscriptions.find_each { |sub| sub.deliver(title: title, body: body, path: path) }
    end
  end
end
