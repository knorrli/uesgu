# Email via Resend (SMTP), mirroring config/initializers/web_push.rb: supply the
# API key through env (RESEND_API_KEY) or credentials (resend.api_key) and email
# turns on; leave it absent and the channel is inert — MailConfig.configured? is
# false, SavedFilter skips email, and delivery falls back to :test so
# nothing leaves the app (dev/CI/first deploy all boot fine).
#
# SMTP, so no extra gem. The sending domain (uesgu.ch — the ASCII code/email
# domain, never the umlaut host) must be verified in Resend for real delivery.
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

  # Public web host for absolute links in emails (the umlaut domain in punycode).
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

# Applied to ActionMailer::Base directly (not via config.action_mailer) so it
# works regardless of initializer ordering — the framework railtie has already
# configured Base by the time custom initializers run.
ActionMailer::Base.default_url_options = { host: MailConfig.web_host, protocol: "https" }
ActionMailer::Base.default_options = { from: MailConfig.from }
ActionMailer::Base.perform_deliveries = true
ActionMailer::Base.raise_delivery_errors = true

# Real SMTP only outside tests — the test env always captures into
# ActionMailer::Base.deliveries so a suite never hits Resend, even though the
# API key is present in shared credentials.
if MailConfig.configured? && !Rails.env.test?
  ActionMailer::Base.delivery_method = :smtp
  ActionMailer::Base.smtp_settings = MailConfig.smtp_settings
else
  ActionMailer::Base.delivery_method = :test
end
