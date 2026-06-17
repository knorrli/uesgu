module NotificationMailerHelper
  # event.url is scraped data, so only ever let an http(s) value become a link in
  # the digest. ERB already escapes the attribute (no markup breakout); this also
  # rejects a malformed/relative URL or a stray javascript: scheme. Returns the
  # safe URL, or nil when there's nothing linkable.
  def digest_event_href(event)
    url = event.url.to_s
    url if url.match?(%r{\Ahttps?://}i)
  end
end
