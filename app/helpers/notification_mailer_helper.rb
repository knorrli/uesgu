module NotificationMailerHelper
  # A solid-colour PNG tile (2x2) as a data URI, used as the background-IMAGE of
  # the OUTER GROUND only. Outlook desktop dark mode (incl. Outlook for Mac, which
  # honors neither prefers-color-scheme nor data-ogsc) recolors background-COLORS
  # but leaves background-images alone — per Microsoft's own guidance this is the
  # only reliable lever — so painting the sand as an image stops Outlook muddying
  # it into olive. We deliberately do NOT image-lock the card: Outlook leaves a
  # bordered content block's background-color light on its own, but if the card
  # carried a background-IMAGE Outlook couldn't read its luminance and flipped the
  # card TEXT to light → washed-out light-on-light. The colour-matched
  # background-color stays as the images-off fallback; the dark @media rule uses
  # `background:` shorthand (which resets background-image), so Apple Mail's dark
  # variant still wins.
  GROUND_TILE = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACAQMAAABIeJ9nAAAAA1BMVEXYz7JN7UBzAAAADElEQVQI12NgYGAAAAAEAAEnNCcKAAAAAElFTkSuQmCC".freeze

  # event.url is scraped data, so only ever let an http(s) value become a link in
  # the digest. ERB already escapes the attribute (no markup breakout); this also
  # rejects a malformed/relative URL or a stray javascript: scheme. Returns the
  # safe URL, or nil when there's nothing linkable.
  def digest_event_href(event)
    url = event.url.to_s
    url if url.match?(%r{\Ahttps?://}i)
  end
end
