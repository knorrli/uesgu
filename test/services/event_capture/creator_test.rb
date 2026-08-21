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

  # Location.hierarchy groups on the literal string, so an uncorrected "bern" is a
  # second node in the WHERE tree forever (see EventCapture::Localities).
  test "a locality differing only in case or accents adopts the stored spelling" do
    venue = Venue.in_taxonomy.find { |v| v.locality.present? }
    skip "no placed venue" if venue.nil?

    result = EventCapture::Creator.call(attrs(place: "", locality: venue.locality.downcase,
                                              canton: venue.canton))

    assert_includes result.event.location_list, venue.locality
  end

  test "a captured locality is reused rather than re-minted in another casing" do
    place(name: "Zorpsaal", locality: "Zorpwil")

    result = EventCapture::Creator.call(attrs(place: "Flarnhalle", locality: "ZORP-WIL"))

    assert_equal "Zorpwil", result.place.locality
    assert_includes result.event.location_list, "Zorpwil"
  end

  # The complement of the case above: a genuine variant is left alone rather than
  # guessed at (see EventCapture::Localities).
  test "a genuinely different spelling is left as typed" do
    place(name: "Zorpsaal", locality: "Zorpwil")

    result = EventCapture::Creator.call(attrs(place: "Flarnhalle", locality: "Zorpvil"))

    assert_equal "Zorpvil", result.place.locality
  end

  # Both lookups match on NAME alone, so the form's locality can disagree with where
  # the place actually is — and the chips would then describe one event two ways.
  test "a matched place is tagged with its own locality and canton, not the form's" do
    place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")

    result = EventCapture::Creator.call(attrs(place: "ZORP-SAAL", locality: "Flarnhausen", canton: "ZH"))

    assert_equal %w[BE Zorpsaal Zorpwil], result.event.location_list.sort
  end

  test "a registry venue is tagged with the registry's own place" do
    venue = Venue.in_taxonomy.first
    skip "no venues in the taxonomy" if venue.nil?

    result = EventCapture::Creator.call(attrs(place: venue.name, locality: "Flarnhausen", canton: "ZH"))

    assert_equal [venue.canton, venue.locality, venue.name].sort, result.event.location_list.sort
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

  # The collision is wanted: a scraper upserts on the url, so pasting a page we
  # already hold means the event exists rather than that something went wrong.
  test "a url the scraper already holds is a duplicate, not a 500" do
    event(url: "https://zorp.example/show", title: "Scraped")

    result = EventCapture::Creator.call(attrs(url: "https://zorp.example/show"))

    assert_equal :duplicate, result.error
  end

  test "two url-less captures both publish" do
    assert_predicate EventCapture::Creator.call(attrs), :ok?
    assert_predicate EventCapture::Creator.call(attrs(title: "Zorp Fest 2")), :ok?
  end

  # This is the only server-side check: the url input's own validation is client-side
  # only, and the value lands in every user's browser (see Creator::HTTP_SCHEMES).
  test "a link that is not http(s) is refused rather than published" do
    assert_equal :url_invalid, EventCapture::Creator.call(attrs(url: "mailto:x@example.com")).error
    assert_equal :url_invalid, EventCapture::Creator.call(attrs(url: "see poster")).error
    assert_equal :url_invalid, EventCapture::Creator.call(attrs(url: "javascript:alert(1)")).error
    assert_predicate EventCapture::Creator.call(attrs(url: "https://zorp.example/x")), :ok?
  end

  # places.url exists to make a VenueLead actionable, and no scraper can be written
  # against someone's Instagram post.
  test "a social link lands on the event but never on the place" do
    result = EventCapture::Creator.call(attrs(url: "https://www.instagram.com/p/zorp"))

    assert_equal "https://www.instagram.com/p/zorp", result.event.url
    assert_nil result.place.url
  end

  test "a venue's own link is kept on the place" do
    result = EventCapture::Creator.call(attrs(url: "https://zorpsaal.example/programm"))

    assert_equal "https://zorpsaal.example/programm", result.place.url
  end

  # A poster prints "25:00" for an after-midnight show, and Time.zone.parse raises on
  # it — a 500 that would take the whole unpersisted queue with it.
  test "an out-of-range clock is nulled, not raised" do
    result = EventCapture::Creator.call(attrs(time: "25:00"))

    assert_predicate result, :ok?
    assert_nil result.event.start_time
  end

  # A correction has to land where the model's own answer would; Time.zone.parse reads
  # every one of these as midnight.
  test "a typed time is read by the same parser the model's answer went through" do
    assert_equal "20:00", EventCapture::Creator.call(attrs(time: "20 Uhr")).event.start_time.strftime("%H:%M")
    assert_equal "20:30", EventCapture::Creator.call(attrs(time: "20h30", title: "B")).event.start_time.strftime("%H:%M")
    assert_nil EventCapture::Creator.call(attrs(time: "abc", title: "C")).event.start_time
    assert_nil EventCapture::Creator.call(attrs(time: "20.08.2026", title: "D")).event.start_time
  end

  # add_to_tree bails on a blank canton exactly as it does on a blank locality.
  test "refuses a candidate with no canton" do
    assert_equal :incomplete, EventCapture::Creator.call(attrs(canton: "")).error
  end

  # The duplicate path raises AFTER the place is written.
  test "a refused publish leaves no orphan place behind" do
    event(url: "https://zorp.example/show", title: "Scraped")

    result = EventCapture::Creator.call(attrs(url: "https://zorp.example/show"))

    assert_equal :duplicate, result.error
    assert_empty Place.all
  end

  # `description` is the curated secondary-text field the scrapers already fill, so a
  # poster's second line needs no column of its own.
  test "the subtitle is published as the event description" do
    assert_equal "message: incomplete",
                 EventCapture::Creator.call(attrs(subtitle: " message: incomplete ")).event.description
    assert_nil EventCapture::Creator.call(attrs(subtitle: "  ", title: "Blank")).event.description
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
