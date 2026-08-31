require "db_test_helper"

class AdminLocalitiesTest < ActionDispatch::IntegrationTest
  def locality(name, canton: nil) = Locality.create!(name: name, canton: canton)

  test "guests are sent to login, non-admins are forbidden" do
    get admin_localities_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get admin_localities_path
    assert_response :forbidden
  end

  test "an admin browses the localities and can filter to the merged ones" do
    zorpwil = locality("Zorpwil", canton: "BE")
    locality("Zorpville").merge_into!(zorpwil)
    sign_in_as user(admin: true)

    get admin_localities_path
    assert_response :success
    assert_select "a", text: "Zorpwil"
    assert_select "a", text: "Zorpville"

    get admin_localities_path(status: "aliased")
    assert_select "a", text: "Zorpville"
    assert_select "a", { text: "Zorpwil", count: 0 }
  end

  test "an admin merges one spelling into another, and the events follow" do
    zorpwil = locality("Zorpwil", canton: "BE")
    zorpville = locality("Zorpville", canton: "BE")
    show = event(location_list: ["Zorpville", "BE"])
    sign_in_as user(admin: true)

    post merge_admin_locality_path(zorpville), params: { locality: { canonical_locality_id: zorpwil.id } }

    assert_redirected_to admin_localities_path
    assert_equal zorpwil, zorpville.reload.canonical
    assert_includes show.reload.location_list, "Zorpwil"
  end

  test "an admin splits a merged locality back out" do
    zorpwil = locality("Zorpwil", canton: "BE")
    zorpville = locality("Zorpville")
    zorpville.merge_into!(zorpwil)
    sign_in_as user(admin: true)

    post unmerge_admin_locality_path(zorpville)

    assert_redirected_to admin_localities_path
    refute_predicate zorpville.reload, :alias?
  end

  test "merging a locality into itself is refused, not crashed on" do
    zorpwil = locality("Zorpwil", canton: "BE")
    sign_in_as user(admin: true)

    post merge_admin_locality_path(zorpwil), params: { locality: { canonical_locality_id: zorpwil.id } }

    assert_redirected_to edit_admin_locality_path(zorpwil)
    refute_predicate zorpwil.reload, :alias?
  end

  test "a registry locality is explained rather than offered a merge form" do
    venue = Venue.in_taxonomy.find { |v| v.locality.present? }
    skip "no placed venue" if venue.nil?
    Locality.reconcile!
    sign_in_as user(admin: true)

    get edit_admin_locality_path(Locality.matching(venue.locality))

    assert_response :success
    assert_select "form[action=?]", merge_admin_locality_path(Locality.matching(venue.locality)), count: 0
  end

  test "the editor offers every other locality as a merge target" do
    zorpwil = locality("Zorpwil", canton: "BE")
    locality("Zorpville", canton: "BE")
    sign_in_as user(admin: true)

    get edit_admin_locality_path(zorpwil)

    assert_response :success
    assert_select "h1", text: "Zorpwil"
    assert_match "Zorpville", response.body
  end
end
