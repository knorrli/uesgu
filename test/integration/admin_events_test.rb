require "db_test_helper"

class AdminEventsTest < ActionDispatch::IntegrationTest
  test "guests are sent to login, non-admins are forbidden" do
    get admin_events_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get admin_events_path
    assert_response :forbidden
  end

  test "an admin can browse, filter and search events" do
    event(title: "Loud Guitars")
    event(title: "Quiet Reading", hidden: true)
    event(title: "Called Off", cancelled_at: Time.utc(2030, 1, 1))
    sign_in_as user(admin: true)

    get admin_events_path
    assert_response :success
    assert_select "a", text: "Loud Guitars"
    assert_select "a", text: "Quiet Reading"

    get admin_events_path(status: "hidden")
    assert_select "a", text: "Quiet Reading"
    assert_select "a", text: "Loud Guitars", count: 0

    get admin_events_path(status: "visible")
    assert_select "a", text: "Loud Guitars"
    assert_select "a", text: "Quiet Reading", count: 0

    get admin_events_path(status: "cancelled")
    assert_select "a", text: "Called Off"
    assert_select "a", text: "Loud Guitars", count: 0

    get admin_events_path(q: "loud")
    assert_select "a", text: "Loud Guitars"
    assert_select "a", text: "Called Off", count: 0
  end

  test "the default date sort lists events chronologically (oldest first)" do
    later = event(title: "LaterShow", start_date: Date.current + 30.days)
    sooner = event(title: "SoonerShow", start_date: Date.current + 2.days)
    sign_in_as user(admin: true)

    get admin_events_path
    assert_response :success
    assert_operator @response.body.index("SoonerShow"), :<, @response.body.index("LaterShow")
  end

  test "the show page renders the edit form and surfaces locked fields" do
    e = event(title: "Editable Show")
    e.lock_field!(:title)
    sign_in_as user(admin: true)

    get admin_event_path(e)
    assert_response :success
    assert_select "input[name=?]", "event[title]"
    assert_select "input[name=?]", "event[date]"
    assert_select "input[name=?]", "event[time]"
    assert_select "form[action=?]", revert_admin_event_path(e, field: "title")
  end

  test "the genre field is named by a label that does not wrap it" do
    e = event(title: "Editable Show")
    sign_in_as user(admin: true)

    get admin_event_path(e)
    assert_select "input#event_genres[role=combobox]"
    assert_select "label[for=?]", "event_genres",
                  text: /#{I18n.t("admin.events.show.genres_label")}/
    assert_select "dialog.hw-combobox__dialog"
    assert_select "label dialog.hw-combobox__dialog", count: 0
  end

  test "editing an event locks only the fields the admin changed" do
    e = event(title: "Wrong Title", description: "Keep Me")
    sign_in_as user(admin: true)

    patch admin_event_path(e), params: { event: {
      title: "Fixed Title", description: "Keep Me",
      date: e.start_date.iso8601, time: "20:30"
    } }
    assert_redirected_to admin_event_path(e)

    e.reload
    assert_equal "Fixed Title", e.title
    assert e.overridden?(:title)
    refute e.overridden?(:description)
    assert e.overridden?(:start_time)
    assert e.overridden?(:start_date)
  end

  test "clearing the time drops it and locks the schedule against the scraper" do
    day = Date.current + 3
    e = event(start_date: day, start_time: Time.zone.local(day.year, day.month, day.day, 20, 30))
    sign_in_as user(admin: true)

    patch admin_event_path(e), params: { event: {
      title: e.title, description: "", date: day.iso8601, time: ""
    } }

    e.reload
    assert_nil e.start_time
    assert_equal day, e.start_date
    assert e.overridden?(:start_time)
    assert e.overridden?(:start_date)
  end

  test "update ignores params outside the editable set" do
    e = event(title: "T")
    original_url = e.url
    sign_in_as user(admin: true)

    patch admin_event_path(e), params: { event: {
      title: "T", description: "", date: e.start_date.iso8601, time: "",
      url: "https://evil.test/changed", hidden: true
    } }

    e.reload
    assert_equal original_url, e.url
    refute e.hidden?
    assert_empty e.overridden_fields
  end

  test "reverting a locked field releases it back to the scraper" do
    e = event
    e.lock_field!(:title)
    sign_in_as user(admin: true)

    patch revert_admin_event_path(e, field: "title")
    assert_redirected_to admin_event_path(e)
    refute e.reload.overridden?(:title)
  end

  test "reverting the schedule releases both date and time" do
    e = event
    e.lock_field!(:start_date)
    e.lock_field!(:start_time)
    sign_in_as user(admin: true)

    patch revert_admin_event_path(e, field: "start_date")

    e.reload
    refute e.overridden?(:start_date)
    refute e.overridden?(:start_time)
  end

  test "editing genres pins the list and re-derives styles, revertible like a scalar" do
    e = event(title: "Genre Show")
    g1 = genre(name: "aaa")
    g2 = genre(name: "bbb")
    sign_in_as user(admin: true)

    patch admin_event_path(e), params: { event: {
      title: "Genre Show", description: "", date: e.start_date.iso8601, time: "",
      genres: "#{g1.name},#{g2.name}"
    } }
    assert_redirected_to admin_event_path(e)

    e.reload
    assert_equal [g1.name, g2.name].sort, e.genre_list.sort
    assert e.overridden?(:genres)

    get admin_event_path(e)
    assert_select "form[action=?]", revert_admin_event_path(e, field: "genres")

    patch revert_admin_event_path(e, field: "genres")
    refute e.reload.overridden?(:genres)
  end

  test "an admin can type a genre the taxonomy has never carried" do
    e = event(title: "Genre Show")
    sign_in_as user(admin: true)

    patch admin_event_path(e), params: { event: {
      title: "Genre Show", description: "", date: e.start_date.iso8601, time: "",
      genres: "zorpcore"
    } }

    assert_equal %w[Zorpcore], e.reload.genre_list
    assert Genre.exists?(fingerprint: Genre.fingerprint_for("zorpcore"))
  end

  test "an admin can dismiss an event and restore it" do
    e = event(title: "Bin Me")
    sign_in_as user(admin: true)

    delete admin_event_path(e)
    assert_redirected_to admin_events_path(status: "dismissed")
    assert e.reload.dismissed?

    patch undismiss_admin_event_path(e)
    assert_redirected_to admin_event_path(e)
    refute e.reload.dismissed?
  end

  test "guests and non-admins cannot dismiss events" do
    e = event(title: "Safe")
    delete admin_event_path(e)
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    delete admin_event_path(e)
    assert_response :forbidden
    refute e.reload.dismissed?
  end

  test "the events list pages with the shared prev/next readout" do
    51.times { |i| event(title: "Show #{format('%02d', i)}") }
    sign_in_as user(admin: true)

    get admin_events_path(sort: "title")
    assert_response :success
    assert_select ".pagination__status", text: /1 .* 2/
    assert_select '.pagination a[rel=next][href*="page=2"]'
    assert_select ".pagination a[rel=prev]", count: 0
    assert_select '.pagination a[rel=next][href*="sort=title"]'

    get admin_events_path(sort: "title", page: 2)
    assert_select '.pagination a[rel=prev][href*="page=1"]'
    assert_select ".pagination a[rel=next]", count: 0
  end

  test "an admin can merge an event into a canonical and split it back out" do
    canonical = event(title: "PETZI Version")
    dup = event(title: "Venue Version")
    sign_in_as user(admin: true)

    patch merge_admin_event_path(dup), params: { canonical_id: canonical.id }
    assert_redirected_to admin_event_path(canonical)
    dup.reload
    assert_equal canonical.id, dup.canonical_event_id
    assert dup.overridden?(:canonical_event), "merge is pinned against dedup"
    refute_includes Event.visible, dup

    patch unmerge_admin_event_path(dup)
    assert_redirected_to admin_event_path(dup)
    assert_nil dup.reload.canonical_event_id
    assert dup.overridden?(:canonical_event), "standalone decision stays pinned"
    assert_includes Event.visible, dup
  end

  test "merging an event into itself is rejected" do
    e = event(title: "Solo")
    sign_in_as user(admin: true)

    patch merge_admin_event_path(e), params: { canonical_id: e.id }
    assert_redirected_to admin_event_path(e)
    assert_nil e.reload.canonical_event_id
  end

  test "merging without picking a canonical is rejected gracefully" do
    e = event(title: "Unpicked")
    sign_in_as user(admin: true)

    patch merge_admin_event_path(e), params: { canonical_id: "" }
    assert_redirected_to admin_event_path(e)
    assert_nil e.reload.canonical_event_id
  end

  test "the merge picker searches canonical events by title, excluding self" do
    current = event(title: "Editing This One")
    match = event(title: "Matching Canonical")
    event(title: "Unrelated")
    sign_in_as user(admin: true)

    get search_admin_events_path(exclude: current.id, q: "Matching", format: :turbo_stream)
    assert_response :success
    assert_match "Matching Canonical", response.body
    assert_no_match "Unrelated", response.body
    assert_no_match "Editing This One", response.body
  end

  test "the show page surfaces the merge form and the duplicate relationship" do
    canonical = event(title: "The Canonical")
    dup = event(title: "The Duplicate")
    dup.merge_into!(canonical)
    sign_in_as user(admin: true)

    get admin_event_path(canonical)
    assert_select "a", text: "The Duplicate"
    assert_select "form[action=?]", merge_admin_event_path(canonical)

    get admin_event_path(dup)
    assert_select "form[action=?]", unmerge_admin_event_path(dup)
  end

  test "guests and non-admins cannot merge events" do
    canonical = event(title: "C")
    dup = event(title: "D")
    patch merge_admin_event_path(dup), params: { canonical_id: canonical.id }
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    patch merge_admin_event_path(dup), params: { canonical_id: canonical.id }
    assert_response :forbidden
    assert_nil dup.reload.canonical_event_id
  end

  test "guests and non-admins cannot edit events" do
    e = event(title: "Untouched")
    patch admin_event_path(e), params: { event: { title: "Hacked", date: e.start_date.iso8601 } }
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    patch admin_event_path(e), params: { event: { title: "Hacked", date: e.start_date.iso8601 } }
    assert_response :forbidden
    assert_equal "Untouched", e.reload.title
  end

  test "the show page offers the venue, locality and canton behind the location tags" do
    venue = place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    e = event(title: "Placed Show")
    e.update!(location_list: [venue.name, venue.locality, venue.canton])
    sign_in_as user(admin: true)

    get admin_event_path(e)
    assert_response :success
    assert_select "input[name=?][value=?]", "event[place]", "Zorpsaal"
    assert_select "input[name=?][value=?]", "event[locality]", "Zorpwil"
    assert_select "select[name=?] option[selected][value=?]", "event[canton]", "BE"
  end

  test "editing the venue rebuilds the location tags, mints the place and pins them" do
    e = event(title: "Wrong Venue")
    e.update!(location_list: %w[Zorpwil BE])
    sign_in_as user(admin: true)

    patch admin_event_path(e), params: { event: {
      title: e.title, description: "", date: e.start_date.iso8601, time: "",
      place: "Zorpkeller", locality: "Zorpwil", canton: "BE"
    } }
    assert_redirected_to admin_event_path(e)

    e.reload
    assert_equal %w[BE Zorpkeller Zorpwil], e.location_list.sort
    assert e.overridden?(:locations)
    assert Place.exists?(fingerprint: Place.fingerprint_for("Zorpkeller"))
  end

  test "a venue that already exists is reused rather than minted a second time" do
    venue = place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    e = event(title: "Placeless")
    sign_in_as user(admin: true)

    assert_no_difference -> { Place.count } do
      patch admin_event_path(e), params: { event: {
        title: e.title, description: "", date: e.start_date.iso8601, time: "",
        place: venue.name, locality: "Zorpwil", canton: "BE"
      } }
    end

    assert_includes e.reload.location_list, venue.name
  end

  test "a submission carrying no locality leaves the location tags untouched" do
    e = event(title: "Keep My Tags")
    e.update!(location_list: %w[Zorpwil BE])
    sign_in_as user(admin: true)

    patch admin_event_path(e), params: { event: {
      title: "Renamed", description: "", date: e.start_date.iso8601, time: ""
    } }

    e.reload
    assert_equal %w[BE Zorpwil], e.location_list.sort
    refute e.overridden?(:locations)
  end

  test "reverting the location releases it back to the scraper" do
    e = event(title: "Pinned Place")
    e.update!(location_list: %w[Zorpwil BE])
    e.lock_field!(:locations)
    sign_in_as user(admin: true)

    get admin_event_path(e)
    assert_select "form[action=?]", revert_admin_event_path(e, field: "locations")

    patch revert_admin_event_path(e, field: "locations")
    refute e.reload.overridden?(:locations)
  end
end
