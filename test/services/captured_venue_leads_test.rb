require "db_test_helper"

# The capture funnel's demand signal: a captured place that keeps hosting shows is
# nominated into the venue-lead inbox. Counted, never classified — every case here is
# about the count and the registry filter, because that is the whole rule.
# Synthetic place names; the registry is read live.
class CapturedVenueLeadsTest < ActiveSupport::TestCase
  def shows_at(place, count)
    count.times { event(location_list: [place.name, place.locality, place.canton]) }
  end

  def leads = VenueLead.where(source: CapturedVenueLeads::SOURCE)

  test "a place with two captured shows is nominated" do
    zorpsaal = place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    shows_at(zorpsaal, 2)

    CapturedVenueLeads.refresh!

    lead = leads.sole
    assert_equal ["Zorpsaal", "Zorpwil", "BE", 2], [lead.venue, lead.locality, lead.canton, lead.event_count]
  end

  # One event cannot answer "should we write a scraper for this?".
  test "a one-off is not a lead" do
    shows_at(place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE"), 1)

    CapturedVenueLeads.refresh!

    assert_empty leads
  end

  # A capture lead's whole basis is an accumulating count, so it must not evaporate
  # as the shows it counted pass.
  test "the count is every show ever captured, not the upcoming ones" do
    zorpsaal = place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    2.times do
      event(start_date: Date.new(2020, 1, 1),
            location_list: [zorpsaal.name, zorpsaal.locality, zorpsaal.canton])
    end

    CapturedVenueLeads.refresh!

    assert_equal 2, leads.sole.event_count
  end

  # Every disposition, not just the consumed ones — which is what makes a
  # `disposition: reject` row the way to turn a nomination down for good.
  test "a place the registry already names in any disposition is not a lead" do
    venue = Venue.all.first
    skip "empty registry" if venue.nil?

    graduated = Place.new(name: venue.name, locality: "Zorpwil", canton: "BE")
    graduated.save!(validate: false)
    shows_at(graduated, 2)

    CapturedVenueLeads.refresh!

    assert_empty leads
  end

  # A merged-away spelling is not a second venue, and its shows are already counted
  # under the name they were folded into.
  test "an alias is not nominated alongside the venue it names" do
    zorpsaal = place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    variant = place(name: "Zorpsaal Halle", locality: "Zorpwil", canton: "BE")
    shows_at(zorpsaal, 1)
    shows_at(variant, 1)

    variant.merge_into!(zorpsaal)
    CapturedVenueLeads.refresh!

    lead = leads.sole
    assert_equal ["Zorpsaal", 2], [lead.venue, lead.event_count]
  end

  test "refreshing replaces this source's leads and leaves an aggregator's alone" do
    VenueLead.refresh!(source: "ole", leads: [{ venue: "Flarnhalle", locality: "Flarnhausen",
                                                canton: "AG", event_count: 7 }])
    shows_at(place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE"), 2)

    CapturedVenueLeads.refresh!
    CapturedVenueLeads.refresh!

    assert_equal 1, leads.count
    assert_equal 7, VenueLead.find_by(source: "ole").event_count
  end

  test "a place that has dropped below the threshold stops being a lead" do
    zorpsaal = place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    shows_at(zorpsaal, 2)
    CapturedVenueLeads.refresh!

    Event.tagged_with("Zorpsaal", on: :locations).first.destroy!
    CapturedVenueLeads.refresh!

    assert_empty leads
  end
end
