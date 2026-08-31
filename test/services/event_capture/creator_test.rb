require "db_test_helper"

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
    second = EventCapture::Creator.call(attrs(place: "ZORP-SAAL", title: "Zorp Fest 2",
                                              acknowledged: "1"))

    assert_equal 1, Place.where(name: "Zorpsaal").count
    assert_equal "Zorpsaal", second.place.name
    assert_includes second.event.location_list, "Zorpsaal"
  end

  test "a registry venue is tagged, never mirrored into places" do
    venue = Venue.in_taxonomy.first
    skip "no venues in the taxonomy" if venue.nil?

    result = EventCapture::Creator.call(attrs(place: venue.name.upcase, locality: venue.locality,
                                              canton: venue.canton))

    assert_predicate result, :ok?
    assert_nil result.place
    assert_empty Place.all
    assert_includes result.event.location_list, venue.name
  end

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

  test "a genuinely different spelling is left as typed" do
    place(name: "Zorpsaal", locality: "Zorpwil")

    result = EventCapture::Creator.call(attrs(place: "Flarnhalle", locality: "Zorpvil"))

    assert_equal "Zorpvil", result.place.locality
  end

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

  test "a blank place publishes without minting one" do
    result = EventCapture::Creator.call(attrs(place: ""))

    assert_predicate result, :ok?
    assert_empty Place.all
    assert_equal %w[BE Zorpwil], result.event.location_list.sort
  end

  test "refuses a candidate missing the fields the tree needs" do
    assert_equal :incomplete, EventCapture::Creator.call(attrs(locality: "")).error
    assert_equal :incomplete, EventCapture::Creator.call(attrs(title: "")).error
    assert_equal :incomplete, EventCapture::Creator.call(attrs(date: "")).error
  end

  test "an unparseable date is refused rather than guessed at" do
    assert_equal :incomplete, EventCapture::Creator.call(attrs(date: "next Friday")).error
  end

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

  test "a captured event carries no url, and several of them publish" do
    first = EventCapture::Creator.call(attrs)
    second = EventCapture::Creator.call(attrs(title: "Zorp Fest 2", acknowledged: "1"))

    assert_predicate first, :ok?
    assert_predicate second, :ok?
    assert_nil first.event.url
    assert_nil second.event.url
  end

  test "a captured place carries no url either" do
    assert_nil EventCapture::Creator.call(attrs).place.url
  end

  test "an out-of-range clock is nulled, not raised" do
    result = EventCapture::Creator.call(attrs(time: "25:00"))

    assert_predicate result, :ok?
    assert_nil result.event.start_time
  end

  test "a typed time is read by the same parser the model's answer went through" do
    assert_equal "20:00", EventCapture::Creator.call(attrs(time: "20 Uhr")).event.start_time.strftime("%H:%M")
    assert_equal "20:30", EventCapture::Creator.call(attrs(time: "20h30", title: "B")).event.start_time.strftime("%H:%M")
    assert_nil EventCapture::Creator.call(attrs(time: "abc", title: "C")).event.start_time
    assert_nil EventCapture::Creator.call(attrs(time: "20.08.2026", title: "D")).event.start_time
  end

  test "refuses a candidate with no canton" do
    assert_equal :incomplete, EventCapture::Creator.call(attrs(canton: "")).error
  end

  test "a publish that raises leaves no orphan place behind" do
    Locality.stub(:ensure!, ->(*) { raise "publish blew up" }) do
      assert_raises(RuntimeError) { EventCapture::Creator.call(attrs) }
    end

    assert_empty Place.all
  end

  test "a venue another capture minted first is a refusal, not a 500" do
    Place.stub(:create, ->(*, **) { raise ActiveRecord::RecordNotUnique }) do
      assert_equal :place_invalid, EventCapture::Creator.call(attrs).error
    end
  end

  test "genres are ensured in the taxonomy and visibility is recomputed" do
    result = EventCapture::Creator.call(attrs(genres: ["Zorpwave", "Flarncore"]))

    assert_equal %w[Flarncore Zorpwave], result.event.genre_list.sort
    assert_equal %w[Flarncore Zorpwave], Genre.where(name: %w[Zorpwave Flarncore]).pluck(:name).sort
    refute_predicate result.event, :hidden?
  end
  class MatchTest < ActiveSupport::TestCase
    def attrs(**overrides)
      { title: "Zorp Fest", date: (Date.current + 20).to_s, time: "20:00", place: "Zorpsaal",
        locality: "Zorpwil", canton: "BE" }.merge(overrides)
    end

    def listed(**overrides)
      event(**{ title: "Zorp Fest", start_date: Date.current + 20,
                location_list: %w[Zorpsaal Zorpwil BE] }.merge(overrides))
    end

    test "a match stops the publish and comes back to be answered" do
      match = listed

      result = EventCapture::Creator.call(attrs)

      refute_predicate result, :ok?
      assert_equal :duplicate, result.error
      assert_equal [match.id], result.matches.map(&:id)
      assert_equal 1, Event.count, "nothing was published"
    end

    test "the check runs on the EDITED values, not the ones the card was rendered with" do
      listed(start_date: Date.current + 21)

      assert_predicate EventCapture::Creator.call(attrs), :ok?
      assert_equal :duplicate, EventCapture::Creator.call(attrs(date: (Date.current + 21).to_s)).error
    end

    test "naming the match keeps the capture and folds it onto that show" do
      match = listed

      result = EventCapture::Creator.call(attrs(matched_event_id: match.id))

      assert_predicate result, :ok?
      assert_equal match, result.canonical
      assert_equal match.id, result.event.canonical_event_id
      refute_includes Event.visible, result.event
      assert_includes Event.visible, match
    end

    test "what the capture read reaches the show it was folded onto" do
      match = listed(description: nil)

      EventCapture::Creator.call(attrs(matched_event_id: match.id, description: "Support: Zorpband",
                                       genres: ["zorpcore"]))

      assert_equal "Support: Zorpband", match.reload.description
      assert_includes match.genre_list.map(&:downcase), "zorpcore"
    end

    test "an answered merge is pinned against the next sweep" do
      match = listed
      result = EventCapture::Creator.call(attrs(matched_event_id: match.id))

      assert result.event.overridden?("canonical_event")
    end

    test "declining the match publishes a second event, pinned standalone" do
      listed

      result = EventCapture::Creator.call(attrs(acknowledged: "1"))

      assert_predicate result, :ok?
      assert_nil result.canonical
      assert_nil result.event.canonical_event_id
      assert result.event.overridden?("canonical_event")
      assert_equal 2, Event.count
    end

    test "a capture with no match to answer pins nothing" do
      result = EventCapture::Creator.call(attrs)

      assert_predicate result, :ok?
      refute result.event.overridden?("canonical_event")
    end

    test "a matched_event_id naming a dismissed event is not merged onto" do
      match = listed
      match.dismiss!

      result = EventCapture::Creator.call(attrs(matched_event_id: match.id, acknowledged: "1"))

      assert_predicate result, :ok?
      assert_nil result.event.canonical_event_id
    end
  end
end
