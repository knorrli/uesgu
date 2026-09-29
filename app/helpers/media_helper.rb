module MediaHelper
  MEDIA_PROVIDER_NAMES = {
    "youtube" => "YouTube", "vimeo" => "Vimeo", "bandcamp" => "Bandcamp",
    "soundcloud" => "SoundCloud", "mixcloud" => "Mixcloud", "spotify" => "Spotify"
  }.freeze

  def media_embed_src(reference)
    id = reference["id"]
    case reference["provider"]
    when "youtube" then "https://www.youtube-nocookie.com/embed/#{id}?autoplay=1&playsinline=1&rel=0"
    when "vimeo" then "https://player.vimeo.com/video/#{id}?autoplay=1&dnt=1"
    when "bandcamp" then "https://bandcamp.com/EmbeddedPlayer/#{id}/size=large/artwork=small/tracklist=false/transparent=true/"
    when "soundcloud" then "https://w.soundcloud.com/player/?#{{ url: soundcloud_url(id), auto_play: true, visual: false }.to_query}"
    when "mixcloud" then "https://player-widget.mixcloud.com/widget/iframe/?#{{ feed: "/#{id}/", mini: 1, autoplay: 1 }.to_query}"
    when "spotify" then "https://open.spotify.com/embed/#{id}"
    end
  end

  def media_page_url(reference)
    id = reference["id"]
    case reference["provider"]
    when "youtube" then "https://www.youtube.com/watch?v=#{id}"
    when "vimeo" then "https://vimeo.com/#{id}"
    when "soundcloud" then "https://soundcloud.com/#{id}" unless id.start_with?("tracks/", "playlists/")
    when "mixcloud" then "https://www.mixcloud.com/#{id}/"
    when "spotify" then "https://open.spotify.com/#{id}"
    end
  end

  def media_play_button(event)
    reference = event.media.first
    return unless reference

    button_tag type: :button,
               class: "event-play icon-button",
               'aria-pressed': "false",
               'aria-label': t("media.play", title: event.title),
               title: t("media.via", provider: MEDIA_PROVIDER_NAMES[reference["provider"]]),
               data: { controller: "media-play", action: "media-play#toggle media:changed@window->media-play#sync",
                       media_play_event_id_value: event.id, media_play_title_value: event.title,
                       media_play_provider_value: reference["provider"], media_play_src_value: media_embed_src(reference),
                       media_play_page_url_value: media_page_url(reference), media_play_event_url_value: media_event_url(event),
                       media_play_provider_name_value: MEDIA_PROVIDER_NAMES[reference["provider"]] } do
      content_tag(:span, "", class: "ph ph-play", 'aria-hidden': true, data: { media_play_target: "icon" })
    end
  end

  def media_event_url(event)
    events_path(day: event.start_date.iso8601, anchor: dom_id(event))
  end

  private

  def soundcloud_url(id)
    id.start_with?("tracks/", "playlists/") ? "https://api.soundcloud.com/#{id}" : "https://soundcloud.com/#{id}"
  end
end
