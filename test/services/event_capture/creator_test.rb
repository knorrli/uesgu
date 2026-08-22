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

  test "the subtitle the contributor kept publishes as the event's description" do
    result = EventCapture::Creator.call(attrs(description: "message: incomplete"))

    assert_equal "message: incomplete", result.event.description
  end

  test "a description nobody filled is nothing, not a blank string" do
    assert_nil EventCapture::Creator.call(attrs(description: "  ")).event.description
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
  # second node in the WHERE tree forever (see Locality).
  test "a locality differing only in case or accents adopts the stored spelling" do
    venue = Venue.in_taxonomy.find { |v| v.locality.present? }
    skip "no placed venue" if venue.nil?
    Locality.reconcile!

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
  # guessed at (see Locality).
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

  # events.url is unique and every captured event leaves it null, which Postgres
  # counts as distinct — the constraint the scrapers upsert on cannot collide two
  # captures.
  test "a captured event carries no url, and several of them publish" do
    first = EventCapture::Creator.call(attrs)
    second = EventCapture::Creator.call(attrs(title: "Zorp Fest 2"))

    assert_predicate first, :ok?
    assert_predicate second, :ok?
    assert_nil first.event.url
    assert_nil second.event.url
  end

  test "a captured place carries no url either" do
    assert_nil EventCapture::Creator.call(attrs).place.url
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

  test "a publish that raises leaves no orphan place behind" do
    Locality.stub(:ensure!, ->(*) { raise "publish blew up" }) do
      assert_raises(RuntimeError) { EventCapture::Creator.call(attrs) }
    end

    assert_empty Place.all
  end

  # Racy by construction: Place#fingerprint_available checks before it writes, so a
  # concurrent capture of the same new venue really does reach the index.
  test "a venue another capture minted first is a refusal, not a 500" do
    Place.stub(:create, ->(*, **) { raise ActiveRecord::RecordNotUnique }) do
      assert_equal :place_invalid, EventCapture::Creator.call(attrs).error
    end
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
