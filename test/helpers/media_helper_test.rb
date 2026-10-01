require "db_test_helper"

class MediaHelperTest < ActionView::TestCase
  include EventsHelper

  attr_accessor :current_user

  def ref(provider, id) = { "provider" => provider, "id" => id }

  test "each provider embeds through its own player host" do
    assert_equal "https://www.youtube-nocookie.com/embed/mI_3DVHXLhM?autoplay=1&playsinline=1&rel=0",
                 media_embed_src(ref("youtube", "mI_3DVHXLhM"))
    assert_equal "https://player.vimeo.com/video/123456789?autoplay=1&dnt=1", media_embed_src(ref("vimeo", "123456789"))
    assert_equal "https://bandcamp.com/EmbeddedPlayer/album=2928376541/size=large/artwork=small/tracklist=false/transparent=true/",
                 media_embed_src(ref("bandcamp", "album=2928376541"))
    assert_equal "https://open.spotify.com/embed/artist/1Deno0E7v6B4caD2VOL1No",
                 media_embed_src(ref("spotify", "artist/1Deno0E7v6B4caD2VOL1No"))
    assert_equal "https://player-widget.mixcloud.com/widget/iframe/?autoplay=1&feed=%2Fsomeone%2Fa-long-mix%2F&hide_cover=1",
                 media_embed_src(ref("mixcloud", "someone/a-long-mix"))
  end

  test "soundcloud embeds without the teaser it lays over its player on phones" do
    assert_includes media_embed_src(ref("soundcloud", "someband/a-song")), "show_teaser=false"
  end

  test "soundcloud embeds a track id through the api and a page path through the site" do
    assert_includes media_embed_src(ref("soundcloud", "tracks/1789018924")),
                    "url=#{CGI.escape('https://api.soundcloud.com/tracks/1789018924')}"
    assert_includes media_embed_src(ref("soundcloud", "someband/a-song")),
                    "url=#{CGI.escape('https://soundcloud.com/someband/a-song')}"
  end

  test "the play button carries every reference's embed in order and loads nothing itself" do
    show = event(title: "Holy Wave", media: [ref("youtube", "cjox_JXa8eM"), ref("spotify", "artist/1Deno0E7v6B4caD2VOL1No")])
    button = Nokogiri::HTML.fragment(media_play_button(show)).at_css("button.event-play")

    assert_equal [
      { "provider" => "youtube", "src" => media_embed_src(ref("youtube", "cjox_JXa8eM")),
        "via" => I18n.t("media.via", provider: "YouTube") },
      { "provider" => "spotify", "src" => media_embed_src(ref("spotify", "artist/1Deno0E7v6B4caD2VOL1No")),
        "via" => I18n.t("media.via", provider: "Spotify") }
    ], JSON.parse(button["data-media-play-media-value"])
    assert_equal "false", button["aria-pressed"]
    assert_equal I18n.t("media.via", provider: "YouTube"), button["title"]
    assert_equal show.url, button["data-media-play-event-url-value"]
    assert_equal "false", button["data-media-play-saved-value"]
    assert_nil button.at_css("iframe, img")
  end

  test "the play button carries whether the viewer saved the event, for the player's heart" do
    show = event(media: [ref("youtube", "cjox_JXa8eM")])
    self.current_user = user
    current_user.event_saves.create!(event: show)
    button = Nokogiri::HTML.fragment(media_play_button(show)).at_css("button.event-play")

    assert_equal "true", button["data-media-play-saved-value"]
  end

  test "an event without media has no play button" do
    assert_nil media_play_button(event(media: []))
  end
end
