module ApplicationHelper
  def share_url_options
    request.host == AppHost::PUBLIC ? { host: AppHost::CODE } : {}
  end

  def external_url(url)
    url.to_s.match?(%r{\Ahttps?://}i) ? url : "#"
  end
end
