require "test_helper"

class Scrapers::MediaTest < Minitest::Test
  def media(html) = Scrapers::Media.in(Nokogiri::HTML(html))

  def ref(provider, id) = { "provider" => provider, "id" => id }

  def test_reads_each_provider_from_embeds_and_links
    found = media(<<~HTML)
      <iframe src="https://www.youtube-nocookie.com/embed/mI_3DVHXLhM?rel=0"></iframe>
      <iframe src="https://player.vimeo.com/video/123456789"></iframe>
      <iframe src="https://bandcamp.com/EmbeddedPlayer/album=2928376541/size=large/"></iframe>
      <iframe src="https://w.soundcloud.com/player/?url=https%3A//api.soundcloud.com/tracks%2F293847561"></iframe>
      <a href="https://www.mixcloud.com/someone/a-long-mix/">mix</a>
    HTML

    assert_equal [ref("youtube", "mI_3DVHXLhM"), ref("vimeo", "123456789"), ref("bandcamp", "album=2928376541"),
                  ref("soundcloud", "tracks/293847561"), ref("mixcloud", "someone/a-long-mix")], found
  end

  def test_reads_spotify_links_across_locales
    found = media('<a href="https://open.spotify.com/intl-de/artist/1Deno0E7v6B4caD2VOL1No">Spotify</a>')

    assert_equal [ref("spotify", "artist/1Deno0E7v6B4caD2VOL1No")], found
  end

  def test_reads_lazy_embeds_from_data_attributes
    found = media('<div data-video-id="https://www.youtube.com/watch?v=kEn5lJTpqg8"></div>')

    assert_equal [ref("youtube", "kEn5lJTpqg8")], found
  end

  def test_reads_click_to_load_placeholders_by_their_thumbnail
    found = media('<div style="background-image:url(https://img.youtube.com/vi/OJb_WomPAuk/hqdefault.jpg)"></div>')

    assert_equal [ref("youtube", "OJb_WomPAuk")], found
  end

  def test_one_video_embedded_and_linked_counts_once
    found = media(<<~HTML)
      <iframe src="https://www.youtube-nocookie.com/embed/CJj1CE9KWc8"></iframe>
      <a href="https://www.youtube.com/watch?v=CJj1CE9KWc8&amp;t=10">watch on YouTube</a>
      <a href="https://youtu.be/CJj1CE9KWc8">short link</a>
    HTML

    assert_equal [ref("youtube", "CJj1CE9KWc8")], found
  end

  def test_ignores_site_chrome
    found = media(<<~HTML)
      <header><a href="https://www.youtube.com/watch?v=AVP0snucUas">trailer</a></header>
      <nav><a href="https://soundcloud.com/venue/radio-show">radio</a></nav>
      <main><a href="https://open.spotify.com/artist/7DJ5eHl9GbONXBmKznV1QG">artist</a></main>
      <aside><iframe src="https://player.vimeo.com/video/987654321"></iframe></aside>
      <footer><a href="https://open.spotify.com/playlist/33h3TGTCgFskLfx7ZDonox">our playlist</a></footer>
    HTML

    assert_equal [ref("spotify", "artist/7DJ5eHl9GbONXBmKznV1QG")], found
  end

  def test_ignores_provider_pages_that_are_not_music
    found = media(<<~HTML)
      <a href="https://www.youtube.com/@venue">channel</a>
      <a href="https://soundcloud.com/pages/cookies">cookies</a>
      <a href="https://bandcamp.com/tag/jazz">tag</a>
      <a href="https://open.spotify.com/user/venue">profile</a>
    HTML

    assert_empty found
  end

  def test_prefers_video_over_spotify_and_keeps_page_order_within_a_provider
    found = media(<<~HTML)
      <a href="https://open.spotify.com/track/6AnDvdMkwAo05xGLLJXKiJ">track</a>
      <a href="https://youtu.be/dC-U0-3yRms">first</a>
      <a href="https://youtu.be/5yWGkZ9-mZE">second</a>
    HTML

    assert_equal [ref("youtube", "dC-U0-3yRms"), ref("youtube", "5yWGkZ9-mZE"),
                  ref("spotify", "track/6AnDvdMkwAo05xGLLJXKiJ")], found
  end

  def test_keeps_at_most_the_limit
    links = 8.times.map { |i| %(<a href="https://youtu.be/video#{i}abcde">#{i}</a>) }.join

    assert_equal Scrapers::Media::LIMIT, media(links).size
  end

  def test_reads_a_mechanize_page
    page = Mechanize::Page.new(URI("https://venue.test/event"), { "content-type" => "text/html" },
                               '<iframe src="https://www.youtube.com/embed/cjox_JXa8eM"></iframe>', "200", Mechanize.new)

    assert_equal [ref("youtube", "cjox_JXa8eM")], Scrapers::Media.in(page)
  end

  def test_content_that_is_not_markup_has_no_media
    assert_empty Scrapers::Media.in({ "video" => "https://youtu.be/dC-U0-3yRms" })
  end
end
