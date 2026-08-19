require "test_helper"

# The adapter itself is a router: SafeFetch decides whether we may fetch, and this
# decides which of the other two adapters the result turned out to be.
class EventCapture::Adapters::UrlTest < ActiveSupport::TestCase
  def fetcher(**attrs)
    result = EventCapture::SafeFetch::Result.new(**attrs)
    Class.new { define_singleton_method(:call) { |_url| result } }
  end

  def call(url, **attrs) = EventCapture::Adapters::Url.call(url, fetcher: fetcher(**attrs))

  test "a fetched page becomes text, stripped of its markup" do
    input = call("https://example.ch/konzerte", content_type: "text/html", url: "https://example.ch/konzerte",
                                                body: "<html><body><h1>Zorpcore</h1><p>Sa 22. August</p></body></html>")

    assert_equal :text, input.kind
    assert_match "Zorpcore", input.text
    refute_match "<h1>", input.text
  end

  test "text/plain is passed through without going near an HTML parser" do
    input = call("https://example.ch/e.txt", content_type: "text/plain", url: "https://example.ch/e.txt",
                                             body: "Zorpcore <not markup> Sa 22. August")

    assert_equal "Zorpcore <not markup> Sa 22. August", input.text
  end

  # Common in a chat message: the link IS the poster.
  test "a directly linked poster becomes an image input" do
    input = call("https://example.ch/poster.jpg", content_type: "image/jpeg", url: "https://example.ch/poster.jpg",
                                                  body: "\xFF\xD8\xFF\xE0".b + ("\0" * 32))

    assert_predicate input, :image?
    assert_equal "image/jpeg", input.media_type
  end

  # Decision 10: a capture keeps ONE url column, and where the paste is the venue's
  # own event page that is exactly the key the scraper later upserts on. The URL
  # the fetch ENDED at is the one carried, not the one typed.
  test "the final URL rides along on whichever input comes out" do
    input = call("https://example.ch/go", content_type: "text/html", url: "https://example.ch/programm/22-08",
                                          body: "<p>Zorpcore</p>")

    assert_equal "https://example.ch/programm/22-08", input.source_url
  end

  test "a fetch refusal is passed through with its code intact" do
    input = call("https://bejazz.ch/programm", code: :robots_disallowed, error: "bejazz.ch/robots.txt disallows this path")

    refute_predicate input, :ok?
    assert_equal :robots_disallowed, input.code
  end

  test "a blank URL never reaches the fetcher" do
    assert_equal :url_empty, EventCapture::Adapters::Url.call("").code
    assert_equal :url_empty, EventCapture::Adapters::Url.call(nil).code
  end
end
