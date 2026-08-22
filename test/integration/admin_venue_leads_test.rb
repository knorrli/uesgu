require "db_test_helper"

# Read-only discovery inbox under /admin/venue_leads: admin-gated. Lists VenueLead
# rows — venues an aggregator surfaced or people kept capturing at, neither in the
# registry — ranked by demand. Synthetic venue names.
class AdminVenueLeadsTest < ActionDispatch::IntegrationTest
  test "guests are sent to login, non-admins are forbidden" do
    get admin_venue_leads_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get admin_venue_leads_path
    assert_response :forbidden
  end

  test "an admin sees the empty state when there are no leads" do
    sign_in_as user(admin: true)

    get admin_venue_leads_path
    assert_response :success
    assert_select "p.muted", text: I18n.t("admin.venue_leads.index.empty")
  end

  test "an admin sees the surfaced leads with place, count and source" do
    VenueLead.refresh!(source: "OLE:TestAgg", leads: [
      { venue: "Glorphalle", locality: "Snarftown", canton: "BE", event_count: 9 },
      { venue: "Blipbar", locality: "Blipcity", canton: "ZH", event_count: 2 }
    ])
    sign_in_as user(admin: true)

    get admin_venue_leads_path
    assert_response :success
    assert_select "span", text: "Glorphalle"
    assert_select "span", text: "Snarftown, BE"
    assert_select "span", text: "Blipbar"
    assert_select "span.chip", text: "OLE:TestAgg", count: 2
  end

  # The two producers rank together, and the source chip is the only thing that says
  # which count means "upcoming" and which means "ever captured".
  test "a nominated place sits in the same ranked list as an aggregator's leads" do
    VenueLead.refresh!(source: "OLE:TestAgg", leads: [
      { venue: "Glorphalle", locality: "Snarftown", canton: "BE", event_count: 9 }
    ])
    zorpsaal = place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    2.times { event(location_list: [zorpsaal.name, zorpsaal.locality, zorpsaal.canton]) }
    CapturedVenueLeads.refresh!
    sign_in_as user(admin: true)

    get admin_venue_leads_path

    assert_response :success
    assert_select "span", text: "Zorpsaal"
    assert_select "span.chip", text: CapturedVenueLeads::SOURCE
    assert_select "span.chip", text: "OLE:TestAgg"
  end
end
