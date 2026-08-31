module MailConfig
  module_function

  def api_key
    ENV["RESEND_API_KEY"].presence || Rails.application.credentials.dig(:resend, :api_key)
  end

  def from
    ENV["MAIL_FROM"].presence || "üsgu <noreply@#{AppHost::CODE}>"
  end

  def configured?
    api_key.present?
  end

  def web_host
    ENV["MAIL_WEB_HOST"].presence || AppHost::PUBLIC
  end

  def smtp_settings
    {
      address: "smtp.resend.com",
      port: 587,
      user_name: "resend",
      password: api_key,
      authentication: :plain,
      enable_starttls_auto: true
    }
  end
end

ActionMailer::Base.default_url_options = { host: MailConfig.web_host, protocol: "https" }
ActionMailer::Base.default_options = { from: MailConfig.from }
ActionMailer::Base.perform_deliveries = true
ActionMailer::Base.raise_delivery_errors = true

if MailConfig.configured? && !Rails.env.test?
  ActionMailer::Base.delivery_method = :smtp
  ActionMailer::Base.smtp_settings = MailConfig.smtp_settings
else
  ActionMailer::Base.delivery_method = :test
end
