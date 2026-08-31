require "db_test_helper"

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

  test "a one-off is not a lead" do
    shows_at(place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE"), 1)

    CapturedVenueLeads.refresh!

    assert_empty leads
  end

  test "the count is every show ever captured, not the upcoming ones" do
    zorpsaal = place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    2.times do
      event(start_date: Date.new(2020, 1, 1),
            location_list: [zorpsaal.name, zorpsaal.locality, zorpsaal.canton])
    end

    CapturedVenueLeads.refresh!

    assert_equal 2, leads.sole.event_count
  end

  test "a place the registry already names in any disposition is not a lead" do
    venue = Venue.all.first
    skip "empty registry" if venue.nil?

    graduated = Place.new(name: venue.name, locality: "Zorpwil", canton: "BE")
    graduated.save!(validate: false)
    shows_at(graduated, 2)

    CapturedVenueLeads.refresh!

    assert_empty leads
  end

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
