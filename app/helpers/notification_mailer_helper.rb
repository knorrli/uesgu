module NotificationMailerHelper
  def digest_event_href(event)
    url = event.url.to_s
    url if url.match?(%r{\Ahttps?://}i)
  end
end
