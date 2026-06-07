class ApplicationController < ActionController::Base
  include Authentication

  before_action :set_locale

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # allow_browser versions: :modern

  private

  # Locale precedence: saved user preference -> browser Accept-Language -> default (de).
  def set_locale
    I18n.locale = preferred_locale || browser_locale || I18n.default_locale
  end

  def preferred_locale
    # `authenticated?` resumes the session so the preference also applies on
    # public pages (which skip require_authentication).
    Current.user&.locale.presence if authenticated?
  end

  def browser_locale
    accept = request.env["HTTP_ACCEPT_LANGUAGE"]
    return if accept.blank?

    accept.split(",")
      .map { |lang| lang.split(";").first.to_s.strip.split("-").first.downcase }
      .find { |lang| I18n.available_locales.map(&:to_s).include?(lang) }
  end
end
