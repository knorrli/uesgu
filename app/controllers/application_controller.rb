class ApplicationController < ActionController::Base
  include Authentication

  before_action :set_locale
  before_action :discourage_indexing

  private

  def discourage_indexing
    response.set_header("X-Robots-Tag", "noindex, nofollow")
  end

  def set_locale
    I18n.locale = preferred_locale || browser_locale || I18n.default_locale
  end

  def preferred_locale
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
