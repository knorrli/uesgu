require "db_test_helper"

class AdminPlacesTest < ActionDispatch::IntegrationTest
  test "guests are sent to login, non-admins are forbidden" do
    get admin_places_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get admin_places_path
    assert_response :forbidden
  end

  test "an admin browses the venues and can filter to the merged ones" do
    akut = place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    place(name: "AKUT Zorpwil", locality: "Zorpwil", canton: "BE").merge_into!(akut)
    sign_in_as user(admin: true)

    get admin_places_path
    assert_response :success
    assert_select "a", text: "AKuT"
    assert_select "a", text: "AKUT Zorpwil"

    get admin_places_path(status: "aliased")
    assert_select "a", text: "AKUT Zorpwil"
    assert_select "a", { text: "AKuT", count: 0 }
  end

  test "an admin merges one spelling into another, and the events follow" do
    akut = place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    variant = place(name: "AKUT Zorpwil", locality: "Zorpwil", canton: "BE")
    show = event(location_list: ["AKUT Zorpwil", "Zorpwil", "BE"])
    sign_in_as user(admin: true)

    post merge_admin_place_path(variant), params: { place: { canonical_place_id: akut.id } }

    assert_redirected_to admin_places_path
    assert_equal akut, variant.reload.canonical
    assert_includes show.reload.location_list, "AKuT"
  end

  test "an admin splits a merged venue back out" do
    akut = place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    variant = place(name: "AKUT Zorpwil", locality: "Zorpwil", canton: "BE")
    variant.merge_into!(akut)
    sign_in_as user(admin: true)

    post unmerge_admin_place_path(variant)

    assert_redirected_to admin_places_path
    refute_predicate variant.reload, :alias?
  end

  test "merging a venue into itself is refused, not crashed on" do
    akut = place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    sign_in_as user(admin: true)

    post merge_admin_place_path(akut), params: { place: { canonical_place_id: akut.id } }

    assert_redirected_to edit_admin_place_path(akut)
    refute_predicate akut.reload, :alias?
  end

  test "a venue the registry has absorbed is explained rather than offered a merge form" do
    venue = Venue.in_taxonomy.first
    skip "no venues in the taxonomy" if venue.nil?
    graduated = Place.new(name: venue.name, locality: venue.locality, canton: venue.canton)
    graduated.save!(validate: false)
    sign_in_as user(admin: true)

    get edit_admin_place_path(graduated)

    assert_response :success
    assert_select "form[action=?]", merge_admin_place_path(graduated), count: 0
  end

  test "the editor offers every other venue as a merge target, labelled with its town" do
    akut = place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    place(name: "Flarnhalle", locality: "Flarnhausen", canton: "AG")
    sign_in_as user(admin: true)

    get edit_admin_place_path(akut)

    assert_response :success
    assert_select "h1", text: "AKuT"
    assert_match "Flarnhalle — Flarnhausen, AG", response.body
  end

  test "an admin fixes a venue's spelling, and the events follow" do
    zorpsaal = place(name: "ZORPSAAL", locality: "Zorpwil", canton: "BE")
    show = event(location_list: ["ZORPSAAL", "Zorpwil", "BE"])
    sign_in_as user(admin: true)

    patch admin_place_path(zorpsaal), params: { place: { name: "Zorpsaal" } }

    assert_redirected_to edit_admin_place_path(zorpsaal)
    assert_equal "Zorpsaal", zorpsaal.reload.name
    assert_includes show.reload.location_list, "Zorpsaal"
    refute_includes show.location_list, "ZORPSAAL"
  end

  test "renaming a venue onto one that already exists comes back with the error" do
    place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    flarnhalle = place(name: "Flarnhalle", locality: "Flarnhausen", canton: "AG")
    sign_in_as user(admin: true)

    patch admin_place_path(flarnhalle), params: { place: { name: "AKuT" } }

    assert_response :unprocessable_entity
    assert_select ".form-errors"
    assert_select "h1", text: "Flarnhalle"
    assert_equal "Flarnhalle", flarnhalle.reload.name
  end

  test "a merged spelling is not offered a rename, the venue it resolves to is" do
    akut = place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    variant = place(name: "AKUT Zorpwil", locality: "Zorpwil", canton: "BE")
    variant.merge_into!(akut)
    sign_in_as user(admin: true)

    get edit_admin_place_path(variant)
    assert_select "form[action=?]", admin_place_path(variant), count: 0

    get edit_admin_place_path(akut)
    assert_select "form[action=?]", admin_place_path(akut)
  end

  test "the return_to round-trip cannot be turned into an open redirect" do
    akut = place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    variant = place(name: "AKUT Zorpwil", locality: "Zorpwil", canton: "BE")
    sign_in_as user(admin: true)

    post merge_admin_place_path(variant), params: { place: { canonical_place_id: akut.id },
                                                    return_to: "https://evil.test/pwn" }

    assert_redirected_to admin_places_path
  end

  test "the index counts the events each venue carries" do
    place(name: "AKuT", locality: "Zorpwil", canton: "BE")
    event(location_list: ["AKuT", "Zorpwil", "BE"])
    sign_in_as user(admin: true)

    get admin_places_path(sort: "count")

    assert_response :success
    assert_select ".catalogue-count", text: /1/
  end

  test "an admin gives a venue a link, and a submit without the field leaves it alone" do
    zorpsaal = place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    sign_in_as user(admin: true)

    patch admin_place_path(zorpsaal), params: { place: { name: "Zorpsaal", url: "https://zorpsaal.test" } }
    assert_redirected_to edit_admin_place_path(zorpsaal)
    assert_equal "https://zorpsaal.test", zorpsaal.reload.url

    get edit_admin_place_path(zorpsaal)
    assert_select "input[name=?][value=?]", "place[url]", "https://zorpsaal.test"

    patch admin_place_path(zorpsaal), params: { place: { name: "Zorpsaal" } }
    assert_equal "https://zorpsaal.test", zorpsaal.reload.url
  end

  test "a blank link is stored as NULL" do
    zorpsaal = place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE", url: "https://zorpsaal.test")
    sign_in_as user(admin: true)

    patch admin_place_path(zorpsaal), params: { place: { name: "Zorpsaal", url: "" } }

    assert_nil zorpsaal.reload.url
  end
end
