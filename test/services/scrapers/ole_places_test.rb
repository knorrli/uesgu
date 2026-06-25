require "db_test_helper"

# The OLE aggregator persists each distinct venue place it resolves (VenuePlace).
# NOTE (2026-06-25): the location taxonomy no longer reads VenuePlace — it reads the
# approved venues in the registry (config/venues.yml via Venue / Location). VenuePlace
# is now written but unread, pending its repurposing into the discovery-lead inbox
# (it records what an aggregator surfaced; a future PR records only the UNAPPROVED
# ones and renames the table). This test still locks the persistence behaviour. Needs
# the DB, so it lives apart from offline ole_test.rb. Synthetic names
# (project-test-synthetic-taxonomy).
class Scrapers::OlePlacesTest < ActiveSupport::TestCase
  def aggregator
    Scrapers::Ole.build(key: "TestAgg", feed_url: "https://agg.example/oleexport", aggregator: true)
  end

  def single_venue
    Scrapers::Ole.build(key: "TestVenue", feed_url: "https://v.example/oleexport",
                        place: ["Venue", "Bern", "BE"])
  end

  test "an aggregator persists each distinct resolved place once" do
    s = aggregator.new
    s.send(:note_place, ["Glorphalle", "Snarftown", "BE"])
    s.send(:note_place, ["Glorphalle", "Snarftown", "BE"]) # duplicate within the run
    s.send(:note_place, ["Blipbar", "Blipcity", "ZH"])

    assert_difference "VenuePlace.count", 2 do
      s.send(:persist_discovered_places)
    end
    assert_equal "OLE:TestAgg", VenuePlace.find_by(venue: "Glorphalle")&.source
  end

  test "a single-venue OLE source records nothing — it is already in the taxonomy" do
    s = single_venue.new
    s.send(:note_place, ["Venue", "Bern", "BE"])

    assert_no_difference "VenuePlace.count" do
      s.send(:persist_discovered_places)
    end
  end

  test "a place too thin to nest (no city) is skipped" do
    s = aggregator.new
    s.send(:note_place, ["LonelyVenue"]) # size 1 — nothing to nest under

    assert_no_difference "VenuePlace.count" do
      s.send(:persist_discovered_places)
    end
  end
end
