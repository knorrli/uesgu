class ApplicationController < ActionController::Base
  include Authentication

  before_action :set_locale
  before_action :discourage_indexing

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # allow_browser versions: :modern

  private

  # üsgu is invite-only — nothing here belongs in a search index or a training
  # corpus. `noindex` drops any page already indexed; `nofollow` is the load-bearing
  # half: the feed's filter chips ACCUMULATE into the active filter (tapping a chip
  # on /events?g[]=Rock yields g[]=Rock&g[]=Metal, and so on), so every page offers
  # ~170 fresh URLs that each offer ~170 more. Left followable, that is a
  # combinatorial crawl trap with no bottom — the one a crawler fell into for ten
  # days in August 2026 at a cost of ~1GB/day.
  #
  # Sent as a header rather than a <meta> tag so it also covers non-HTML responses
  # (the ICS feed, turbo-stream fragments), and so a crawler sees it on a HEAD
  # request without fetching a body. robots.txt says the same thing; this is what
  # the crawlers that skip robots.txt still have to read.
  def discourage_indexing
    response.set_header("X-Robots-Tag", "noindex, nofollow")
  end

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
