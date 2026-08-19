require "db_test_helper"

# The publish half: one verified candidate in, one live Event out. This is the
# first and only thing in the funnel that writes, so what it refuses matters as
# much as what it creates. Synthetic place names; the registry is read live.
class EventCapture::CreatorTest < ActiveSupport::TestCase
  def attrs(**overrides)
    { title: "Zorp Fest", date: "2026-09-01", time: "20:00", place: "Zorpsaal",
      locality: "Zorpwil", canton: "BE" }.merge(overrides)
  end

  test "publishes an event located by place, locality and canton" do
    result = EventCapture::Creator.call(attrs)

    assert_predicate result, :ok?
    assert_equal "Zorp Fest", result.event.title
    assert_equal Date.new(2026, 9, 1), result.event.start_date
    assert_equal %w[BE Zorpsaal Zorpwil], result.event.location_list.sort
  end

  # The seam that keeps a captured event out of the scrapers' nightly
  # re-derivation.
  test "stamps the capture data source" do
    assert_equal "capture", EventCapture::Creator.call(attrs).event.data_source
  end

  test "mints the captured place, once, and reuses it for a variant spelling" do
    EventCapture::Creator.call(attrs)
    second = EventCapture::Creator.call(attrs(place: "ZORP-SAAL", title: "Zorp Fest 2"))

    assert_equal 1, Place.where(name: "Zorpsaal").count
    assert_equal "Zorpsaal", second.place.name
    assert_includes second.event.location_list, "Zorpsaal"
  end

  # The most valuable outcome of match-at-entry: tag the event and write no Place.
  test "a registry venue is tagged, never mirrored into places" do
    venue = Venue.in_taxonomy.first
    skip "no venues in the taxonomy" if venue.nil?

    result = EventCapture::Creator.call(attrs(place: venue.name.upcase, locality: venue.locality,
                                              canton: venue.canton))

    assert_predicate result, :ok?
    assert_nil result.place
    assert_empty Place.all
    # The REGISTRY's spelling, not the contributor's: a venue's name must equal the
    # location tag its events carry, or the taxonomy stops resolving it.
    assert_includes result.event.location_list, venue.name
  end

  # A show in a park: located by locality + canton alone, which is still a node
  # the WHERE tree can reach.
  test "a blank place publishes without minting one" do
    result = EventCapture::Creator.call(attrs(place: ""))

    assert_predicate result, :ok?
    assert_empty Place.all
    assert_equal %w[BE Zorpwil], result.event.location_list.sort
  end

  # Location.add_to_tree drops any tuple missing the middle tier, so a blank
  # locality is an event nobody can browse to.
  test "refuses a candidate missing the fields the tree needs" do
    assert_equal :incomplete, EventCapture::Creator.call(attrs(locality: "")).error
    assert_equal :incomplete, EventCapture::Creator.call(attrs(title: "")).error
    assert_equal :incomplete, EventCapture::Creator.call(attrs(date: "")).error
  end

  test "an unparseable date is refused rather than guessed at" do
    assert_equal :incomplete, EventCapture::Creator.call(attrs(date: "next Friday")).error
  end

  # A poster that never printed a time must not read as a show starting at 00:00.
  test "no time leaves start_time null rather than inventing midnight" do
    result = EventCapture::Creator.call(attrs(time: ""))

    assert_predicate result, :ok?
    assert_nil result.event.start_time
    assert_equal Date.new(2026, 9, 1), result.event.start_date
  end

  test "a time is stored against the captured date" do
    event = EventCapture::Creator.call(attrs).event

    assert_equal "2026-09-01 20:00", event.start_time.strftime("%Y-%m-%d %H:%M")
  end

  # Decision 10 chose this collision deliberately: the scraper's upsert key is the
  # url, so a paste of a page we already have is "this event already exists".
  test "a url the scraper already holds is a duplicate, not a 500" do
    event(url: "https://zorp.example/show", title: "Scraped")

    result = EventCapture::Creator.call(attrs(url: "https://zorp.example/show"))

    assert_equal :duplicate, result.error
  end

  test "two url-less captures both publish" do
    assert_predicate EventCapture::Creator.call(attrs), :ok?
    assert_predicate EventCapture::Creator.call(attrs(title: "Zorp Fest 2")), :ok?
  end

  # places.url exists to make a VenueLead actionable ("write a scraper"), and a
  # scraper cannot be written against someone's Instagram post.
  test "a social link lands on the event but never on the place" do
    result = EventCapture::Creator.call(attrs(url: "https://www.instagram.com/p/zorp"))

    assert_equal "https://www.instagram.com/p/zorp", result.event.url
    assert_nil result.place.url
  end

  test "a venue's own link is kept on the place" do
    result = EventCapture::Creator.call(attrs(url: "https://zorpsaal.example/programm"))

    assert_equal "https://zorpsaal.example/programm", result.place.url
  end

  # Captured genres join the taxonomy exactly like scraped ones, and a capture
  # carrying only non-music genres is hidden by the same rule.
  test "genres are ensured in the taxonomy and visibility is recomputed" do
    result = EventCapture::Creator.call(attrs(genres: ["Zorpwave", "Flarncore"]))

    assert_equal %w[Flarncore Zorpwave], result.event.genre_list.sort
    assert_equal %w[Flarncore Zorpwave], Genre.where(name: %w[Zorpwave Flarncore]).pluck(:name).sort
    refute_predicate result.event, :hidden?
  end
end
