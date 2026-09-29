require "db_test_helper"

class MediaHelperTest < ActionView::TestCase
  include EventsHelper

  def ref(provider, id) = { "provider" => provider, "id" => id }

  test "each provider embeds through its own player host" do
    assert_equal "https://www.youtube-nocookie.com/embed/mI_3DVHXLhM?autoplay=1&playsinline=1&rel=0",
                 media_embed_src(ref("youtube", "mI_3DVHXLhM"))
    assert_equal "https://player.vimeo.com/video/123456789?autoplay=1&dnt=1", media_embed_src(ref("vimeo", "123456789"))
    assert_equal "https://bandcamp.com/EmbeddedPlayer/album=2928376541/size=large/artwork=small/tracklist=false/transparent=true/",
                 media_embed_src(ref("bandcamp", "album=2928376541"))
    assert_equal "https://open.spotify.com/embed/artist/1Deno0E7v6B4caD2VOL1No",
                 media_embed_src(ref("spotify", "artist/1Deno0E7v6B4caD2VOL1No"))
    assert_equal "https://player-widget.mixcloud.com/widget/iframe/?autoplay=1&feed=%2Fsomeone%2Fa-long-mix%2F&mini=1",
                 media_embed_src(ref("mixcloud", "someone/a-long-mix"))
  end

  test "soundcloud embeds a track id through the api and a page path through the site" do
    assert_includes media_embed_src(ref("soundcloud", "tracks/1789018924")),
                    "url=#{CGI.escape('https://api.soundcloud.com/tracks/1789018924')}"
    assert_includes media_embed_src(ref("soundcloud", "someband/a-song")),
                    "url=#{CGI.escape('https://soundcloud.com/someband/a-song')}"
  end

  test "each reference with a public page links to it on the provider's site" do
    assert_equal "https://www.youtube.com/watch?v=mI_3DVHXLhM", media_page_url(ref("youtube", "mI_3DVHXLhM"))
    assert_equal "https://vimeo.com/123456789", media_page_url(ref("vimeo", "123456789"))
    assert_equal "https://soundcloud.com/someband/a-song", media_page_url(ref("soundcloud", "someband/a-song"))
    assert_equal "https://www.mixcloud.com/someone/a-long-mix/", media_page_url(ref("mixcloud", "someone/a-long-mix"))
    assert_equal "https://open.spotify.com/artist/1Deno0E7v6B4caD2VOL1No",
                 media_page_url(ref("spotify", "artist/1Deno0E7v6B4caD2VOL1No"))
  end

  test "embeds addressed by numeric id have no public page to link" do
    assert_nil media_page_url(ref("soundcloud", "tracks/1789018924"))
    assert_nil media_page_url(ref("bandcamp", "album=2928376541"))
  end

  test "the play button carries the first reference's embed and loads nothing itself" do
    show = event(title: "Holy Wave", media: [ref("youtube", "cjox_JXa8eM"), ref("spotify", "artist/1Deno0E7v6B4caD2VOL1No")])
    button = Nokogiri::HTML.fragment(media_play_button(show)).at_css("button.event-play")

    assert_equal "youtube", button["data-media-play-provider-value"]
    assert_equal media_embed_src(ref("youtube", "cjox_JXa8eM")), button["data-media-play-src-value"]
    assert_equal "https://www.youtube.com/watch?v=cjox_JXa8eM", button["data-media-play-page-url-value"]
    assert_equal "YouTube", button["data-media-play-provider-name-value"]
    assert_equal "false", button["aria-pressed"]
    assert_equal I18n.t("media.via", provider: "YouTube"), button["title"]
    assert_equal show.url, button["data-media-play-event-url-value"]
    assert_nil button.at_css("iframe, img")
  end

  test "an event without media has no play button" do
    assert_nil media_play_button(event(media: []))
  end
end
