require "db_test_helper"

class Scrapers::OleLeadsTest < ActiveSupport::TestCase
  def aggregator
    Scrapers::Ole.build(key: "TestAgg", feed_url: "https://agg.example/oleexport", aggregator: true)
  end

  def single_venue
    Scrapers::Ole.build(key: "TestVenue", feed_url: "https://v.example/oleexport",
                        place: ["Venue", "Bern", "BE"])
  end

  test "an aggregator records UNSEEN resolved venues as leads, with accumulated counts" do
    s = aggregator.new
    s.send(:note_place, ["Glorphalle", "Snarftown", "BE"], 3)
    s.send(:note_place, ["Glorphalle", "Snarftown", "BE"], 2)
    s.send(:note_place, ["Blipbar", "Blipcity", "ZH"], 1)

    assert_difference "VenueLead.count", 2 do
      s.send(:persist_leads)
    end
    glorph = VenueLead.find_by(venue: "Glorphalle")
    assert_equal 5, glorph.event_count, "counts accumulate across the run"
    assert_equal "OLE:TestAgg", glorph.source
  end

  test "a CONSUME registry venue is ingested, not recorded as a lead" do
    s = aggregator.new
    s.send(:note_place, ["Dachstock", "Bern", "BE"], 4)

    assert_no_difference "VenueLead.count" do
      s.send(:persist_leads)
    end
  end

  test "a REJECTED registry venue is not recorded as a lead (already triaged)" do
    s = aggregator.new
    s.send(:note_place, ["La Cappella", "Bern", "BE"], 2)

    assert_no_difference "VenueLead.count" do
      s.send(:persist_leads)
    end
  end

  test "a single-venue OLE source records no leads" do
    s = single_venue.new
    s.send(:note_place, ["Venue", "Bern", "BE"], 2)

    assert_no_difference "VenueLead.count" do
      s.send(:persist_leads)
    end
  end

  test "a place too thin to nest (no locality) is skipped" do
    s = aggregator.new
    s.send(:note_place, ["LonelyVenue"], 1)

    assert_no_difference "VenueLead.count" do
      s.send(:persist_leads)
    end
  end
end
