# A single browser/device a user has opted in to receive Web Push on. A user can
# have several (phone, laptop). The endpoint + keys come from the browser's
# PushManager.subscribe(); we POST an encrypted, VAPID-signed payload to the
# endpoint and the device's service worker shows the OS notification.
class PushSubscription < ApplicationRecord
  belongs_to :user

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh_key, :auth_key, presence: true

  # Send one notification to this device. Returns true on success. Subscriptions
  # die quietly (user revokes permission, clears data, reinstalls): the push
  # service answers 404/410, and we prune the row so we stop trying. Other
  # transient errors are logged and swallowed so one dead endpoint can't abort a
  # whole digest run.
  def deliver(title:, body:, path: "/")
    return false unless WebPushConfig.configured?

    # Declarative Web Push (https://webkit.org/blog/16535/): the payload itself carries
    # the notification and a `navigate` URL, so iOS 18.4+ shows it and deep-links on tap
    # NATIVELY. This is essential — iOS does not fire the service worker's
    # notificationclick for an already-running standalone PWA, so it's the only way to
    # open the right page there. Browsers that don't recognise the `web_push: 8030`
    # magic key (Chrome/Android, desktop) ignore it and fall back to the service worker
    # push event, which reads the same payload and deep-links from notificationclick
    # (see app/views/pwa/service-worker.js). `navigate` must be absolute and on the
    # PUBLIC punycode origin the installed PWA runs on, or iOS opens it outside the app.
    WebPush.payload_send(
      message: JSON.generate(
        web_push: 8030,
        notification: { title: title, body: body, navigate: "https://#{AppHost::PUBLIC}#{path}" }
      ),
      endpoint: endpoint,
      p256dh: p256dh_key,
      auth: auth_key,
      vapid: WebPushConfig.vapid,
      urgency: "normal"
    )
    update_column(:last_pushed_at, Time.current)
    true
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
    destroy
    false
  rescue WebPush::Error => e
    Rails.logger.warn("[web_push] delivery failed for subscription ##{id}: #{e.class} #{e.message}")
    false
  end
end
