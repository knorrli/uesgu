require "db_test_helper"

# Read-only discovery inbox under /admin/venue_leads: admin-gated. Lists VenueLead
# rows (aggregator-surfaced venues not in the registry) ranked by demand. Synthetic
# venue names (project-test-synthetic-taxonomy).
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
      { venue: "Glorphalle", city: "Snarftown", canton: "BE", event_count: 9 },
      { venue: "Blipbar", city: "Blipcity", canton: "ZH", event_count: 2 }
    ])
    sign_in_as user(admin: true)

    get admin_venue_leads_path
    assert_response :success
    assert_select "span", text: "Glorphalle"
    assert_select "span", text: "Snarftown, BE"
    assert_select "span", text: "Blipbar"
    assert_select "span.chip", text: "OLE:TestAgg", count: 2
  end
end
