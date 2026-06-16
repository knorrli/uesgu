# VAPID configuration for Web Push. The keypair identifies *this* application to
# the browser push services (FCM, Mozilla autopush, Apple) when we send a push.
#
# Generate a keypair once with `rake web_push:generate_keys`, then supply it via
# env (VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY) — on Render as service env vars, in
# development via .env / the shell. The public key is also handed to the browser
# at subscribe time; the private key signs each push and must stay secret.
#
# When the keys are absent the feature is simply inert: WebPushConfig.configured?
# is false, the settings UI hides the opt-in, and WebPushNotifier sends nothing.
# So the app boots fine without any push setup (dev, test, first deploy).
module WebPushConfig
  module_function

  def public_key
    ENV["VAPID_PUBLIC_KEY"].presence || Rails.application.credentials.dig(:vapid, :public_key)
  end

  def private_key
    ENV["VAPID_PRIVATE_KEY"].presence || Rails.application.credentials.dig(:vapid, :private_key)
  end

  # The "subject" is a contact URL the push service can use to reach us about our
  # traffic. AppHost::CODE is the canonical code/email domain (never the umlaut host).
  def subject
    ENV["VAPID_SUBJECT"].presence || "mailto:hello@#{AppHost::CODE}"
  end

  def configured?
    public_key.present? && private_key.present?
  end

  # The hash shape web-push expects for VAPID-signed delivery.
  def vapid
    { subject: subject, public_key: public_key, private_key: private_key }
  end
end
