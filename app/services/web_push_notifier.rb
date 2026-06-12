# Turns freshly-sealed notification digests into Web Push deliveries — the third
# delivery channel alongside the in-app bell and (later) email. All three read
# from the same digest the cadence engine already produces; this one just fans a
# digest out to the user's devices.
#
# Gating: an in-app digest is created whenever *any* new event lands, so the
# unread count stays truthful. Push, by contrast, only fires when the window
# holds events that actually match the user's favorites (locations OR styles) —
# pushing "0 relevant" to someone's phone is exactly the noise we don't want.
class WebPushNotifier
  # `digests` is the array Notification.generate_for returned for one user (the
  # windows just sealed). Several can seal at once when a user hasn't been
  # notified in a while; we collapse them into a single push so a long gap never
  # buzzes a device repeatedly.
  def self.deliver_digests(user, digests)
    new(user, digests).deliver
  end

  def initialize(user, digests)
    @user = user
    @digests = Array(digests)
  end

  def deliver
    return unless WebPushConfig.configured?
    return if @digests.empty?
    return if @user.push_subscriptions.none?

    relevant = relevant_counts
    return if relevant.empty?

    total = relevant.sum { |(_, count)| count }
    target = relevant.max_by { |(digest, _)| digest.period_end }.first

    I18n.with_locale(@user.locale.presence || I18n.default_locale) do
      title = I18n.t("push.digest.title")
      body = I18n.t("push.digest.body", count: total)
      @user.push_subscriptions.find_each { |sub| sub.deliver(title: title, body: body, path: path_for(target)) }
    end
  end

  private

  # [[digest, relevant_count], ...] for the windows that have at least one event
  # matching the user's favorites. Counted once here so deliver doesn't re-query.
  def relevant_counts
    @digests.map { |digest| [digest, digest.relevant_events.count] }
            .reject { |(_, count)| count.zero? }
  end

  def path_for(digest)
    Rails.application.routes.url_helpers.notification_path(digest)
  end
end
