module ApplicationHelper
  # Extra options for *url helpers that build shareable/copyable links (signup
  # invites, the ICS feed). In production we serve from the umlaut domain üsgu.ch,
  # but its on-the-wire punycode form (AppHost::PUBLIC) is what leaks into copied
  # link *text* — ugly and IDN-unfriendly to paste. So when (and only when) the
  # request is on that punycode host, mint the link against the ASCII twin
  # (AppHost::CODE) instead; routes.rb 301s it back, preserving path + query, so
  # browsers and calendar clients still land on the real page.
  #
  # Any other host — localhost in dev, a Render preview, a test — is left alone,
  # so *url falls back to the request host (and port) as usual and links stay
  # clickable where they're generated.
  def share_url_options
    request.host == AppHost::PUBLIC ? { host: AppHost::CODE } : {}
  end
end
