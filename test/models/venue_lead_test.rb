require "db_test_helper"

# VenueLead is the discovery inbox: aggregator-resolved venues NOT approved in the
# registry, rewritten fresh per source each run, ranked by upcoming-event demand.
# Synthetic names (project-test-synthetic-taxonomy).
class VenueLeadTest < ActiveSupport::TestCase
  test "refresh! replaces a source's leads with the current run's set" do
    VenueLead.create!(venue: "Stale", city: "X", canton: "BE", source: "OLE:Test", event_count: 1)

    VenueLead.refresh!(source: "OLE:Test", leads: [
      { venue: "Glorphalle", city: "Snarftown", canton: "BE", event_count: 5 },
      { venue: "Blipbar", city: "Blipcity", canton: "ZH", event_count: 2 }
    ])

    assert_equal %w[Blipbar Glorphalle], VenueLead.where(source: "OLE:Test").pluck(:venue).sort,
                 "the stale lead is dropped and the current run's leads kept"
  end

  test "refresh! leaves other sources untouched" do
    VenueLead.create!(venue: "Keep", city: "X", canton: "BE", source: "OLE:Other", event_count: 1)

    VenueLead.refresh!(source: "OLE:Test", leads: [{ venue: "New", city: "Y", canton: "ZH", event_count: 3 }])

    assert VenueLead.exists?(venue: "Keep", source: "OLE:Other")
  end

  test "by_demand ranks the highest event_count first" do
    VenueLead.refresh!(source: "OLE:Test", leads: [
      { venue: "Low", city: "X", canton: "BE", event_count: 1 },
      { venue: "High", city: "Y", canton: "BE", event_count: 9 }
    ])

    assert_equal %w[High Low], VenueLead.by_demand.pluck(:venue)
  end

  test "venue and source are required" do
    assert_raises(ActiveRecord::RecordInvalid) do
      VenueLead.create!(venue: nil, city: "X", canton: "BE", source: "OLE:Test")
    end
  end
end
