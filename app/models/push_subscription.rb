class PushSubscription < ApplicationRecord
  belongs_to :user

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh_key, :auth_key, presence: true

  def deliver(title:, body:, path: "/")
    return false unless WebPushConfig.configured?

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
