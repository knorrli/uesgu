module NotificationMailerHelper
  # Solid-colour PNG tiles (2x2) as data URIs, used as background-IMAGES on the
  # ground + card. Outlook desktop dark mode (incl. Outlook for Mac, which honors
  # neither prefers-color-scheme nor data-ogsc) recolors background-COLORS but
  # leaves background-images alone — per Microsoft's own guidance this is the only
  # reliable lever, so painting the colour as an image stops Outlook muddying the
  # cream ground into olive. The colour-matched background-color stays as the
  # fallback for images-off / clients that drop the data URI; the dark @media rule
  # uses `background:` shorthand, which resets background-image, so Apple Mail's
  # dark variant still wins.
  GROUND_TILE = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACAQMAAABIeJ9nAAAAA1BMVEXYz7JN7UBzAAAADElEQVQI12NgYGAAAAAEAAEnNCcKAAAAAElFTkSuQmCC".freeze
  CARD_TILE   = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACAQMAAABIeJ9nAAAAA1BMVEXo4c2iO8BiAAAADElEQVQI12NgYGAAAAAEAAEnNCcKAAAAAElFTkSuQmCC".freeze

  # event.url is scraped data, so only ever let an http(s) value become a link in
  # the digest. ERB already escapes the attribute (no markup breakout); this also
  # rejects a malformed/relative URL or a stray javascript: scheme. Returns the
  # safe URL, or nil when there's nothing linkable.
  def digest_event_href(event)
    url = event.url.to_s
    url if url.match?(%r{\Ahttps?://}i)
  end
end
