module WebPushConfig
  module_function

  def public_key
    ENV["VAPID_PUBLIC_KEY"].presence || Rails.application.credentials.dig(:vapid, :public_key)
  end

  def private_key
    ENV["VAPID_PRIVATE_KEY"].presence || Rails.application.credentials.dig(:vapid, :private_key)
  end

  def subject
    ENV["VAPID_SUBJECT"].presence || "mailto:hello@#{AppHost::CODE}"
  end

  def configured?
    public_key.present? && private_key.present?
  end

  def vapid
    { subject: subject, public_key: public_key, private_key: private_key }
  end
end
