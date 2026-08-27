require "db_test_helper"

# Read-only locations browser under /admin/locations: admin-gated. Locations
# have no table — the type (venue / locality / canton) is derived from the scrapers
# via Location.type_for — so the type filter is exercised with a real venue and
# canton (scraper code, not churned taxonomy) plus a synthetic locality.
class AdminLocationsTest < ActionDispatch::IntegrationTest
  test "guests are sent to login, non-admins are forbidden" do
    get admin_locations_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get admin_locations_path
    assert_response :forbidden
  end

  # This browser filters on `type` where every other catalogue filters on `status`,
  # so the shared controls take it as a local — pass the wrong one and the chips
  # still render, they just filter nothing.
  test "the type chips and the sort row carry each other's param" do
    event(location_list: ["Synthville", Location.canton_codes.first])
    sign_in_as user(admin: true)

    get admin_locations_path(sort: "count")
    assert_select "a.tag[href=?]", admin_locations_path(type: "locality", sort: "count")

    get admin_locations_path(type: "locality")
    assert_select ".catalogue-sort-option[href=?]", admin_locations_path(type: "locality", sort: "count")
  end

  test "an admin can browse locations classified by type" do
    venue = Location.venue_names.first
    canton = Location.canton_codes.first
    event(location_list: [venue, "Synthville", canton])
    sign_in_as user(admin: true)

    get admin_locations_path
    assert_response :success
    assert_select "a", text: venue
    assert_select "a", text: "Synthville"

    get admin_locations_path(type: "venue")
    assert_select "a", text: venue
    assert_select "a", text: "Synthville", count: 0

    get admin_locations_path(type: "locality")
    assert_select "a", text: "Synthville"
    assert_select "a", text: venue, count: 0

    get admin_locations_path(q: "synth")
    assert_select "a", text: "Synthville"
  end
end
