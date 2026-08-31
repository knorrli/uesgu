require "db_test_helper"

class EventsIndexTest < ActionDispatch::IntegrationTest
  test "index is public and shows visible events but not hidden ones" do
    event(title: "VisibleMarkerShow", start_date: Date.current + 3.days)
    event(title: "HiddenMarkerShow", start_date: Date.current + 3.days, hidden: true)

    get events_path

    assert_response :success
    assert_includes response.body, "VisibleMarkerShow"
    refute_includes response.body, "HiddenMarkerShow"
  end

  test "a scraped event's title links out, marker and all" do
    e = event(title: "LinkedShow", start_date: Date.current + 3, url: "https://venue.test/show")

    get events_path

    assert_select "##{ActionView::RecordIdentifier.dom_id(e)} .event-title a[href=?]", e.url do
      assert_select ".event-link-marker"
    end
  end

  test "a captured event carries no url, so its title is plain text" do
    e = event(title: "CapturedShow", start_date: Date.current + 3, url: nil)

    get events_path

    assert_includes response.body, "CapturedShow"
    assert_select "##{ActionView::RecordIdentifier.dom_id(e)} .event-title" do
      assert_select "a", false, "nothing to link to"
      assert_select ".event-link-marker", false, "and no arrow promising one"
    end
  end

  test "a captured event is marked Community, a scraped one is not" do
    captured = event(title: "CommunityShow", start_date: Date.current + 3, url: nil,
                     data_source: EventCapture::Creator::DATA_SOURCE)
    scraped = event(title: "ScrapedShow", start_date: Date.current + 3,
                    url: "https://venue.test/show", data_source: "OLE:Klangkeller")

    get events_path

    assert_select "##{ActionView::RecordIdentifier.dom_id(captured)} .event-title .chip--community"
    assert_select "##{ActionView::RecordIdentifier.dom_id(scraped)} .event-title .chip--community", false,
                  "a scraper re-derives its events nightly, so they carry no provenance caveat"
  end

  test "the empty-state reflects whole-filter matches, not the current page" do
    event(title: "DarksideShow", start_date: Date.current + 2.months)

    get events_path(q: ["DarksideShow"], page: 2)
    assert_response :success
    assert_select "p.events-empty", false

    get events_path(q: ["NoSuchEventAnywhere"])
    assert_select "p.events-empty"
  end

  test "a location filter narrows the listing" do
    event(title: "AlphaShow", location_list: ["VenueAlpha"], start_date: Date.current + 2.days)
    event(title: "BetaShow", location_list: ["VenueBeta"], start_date: Date.current + 2.days)

    get events_path(l: "VenueAlpha")

    assert_response :success
    assert_includes response.body, "AlphaShow"
    refute_includes response.body, "BetaShow"
  end

  test "a text query filters by title" do
    event(title: "FindMeUnique", start_date: Date.current + 2.days)
    event(title: "OtherUnique", start_date: Date.current + 2.days)

    get events_path(q: ["FindMeUnique"])

    assert_includes response.body, "FindMeUnique"
    refute_includes response.body, "OtherUnique"
  end

  test "the filter summary row is always present so applying a filter never shifts the layout" do
    event(title: "AnyShow", start_date: Date.current + 2.days)

    get events_path
    assert_select ".filter-sheets__summary.filter-sheets__summary--empty"
    assert_select ".filter-sheets__summary .filter-chip", false

    get events_path(q: ["AnyShow"])
    assert_select ".filter-sheets__summary--empty", false
    assert_select ".filter-sheets__summary .filter-chip"
  end

  test "a freetext term lights a genre tag whose name contains it, and tapping clears it" do
    event(title: "NoMatchTitle", genre_list: ["Quophop"], start_date: Date.current + 2.days)

    get events_path(q: ["hop"])

    assert_response :success
    assert_includes response.body, "NoMatchTitle"
    assert_select "a.filter-link.active[href=?]", events_path(filtered: 1), text: "Quophop"
  end

  test "an applied filter is remembered and replayed on a later plain visit" do
    event(title: "JazzNightShow", genre_list: ["Jazzy"], start_date: Date.current + 2.days)

    get events_path(filtered: 1, g: ["Jazzy"])
    assert_redirected_to events_path(g: ["Jazzy"])
    follow_redirect!
    assert_response :success

    get events_path
    assert_redirected_to events_path(g: ["Jazzy"])
  end

  test "a shared filter link renders directly and is then remembered" do
    event(title: "JazzNightShow", genre_list: ["Jazzy"], start_date: Date.current + 2.days)

    get events_path(g: ["Jazzy"])
    assert_response :success
    get events_path
    assert_redirected_to events_path(g: ["Jazzy"])
  end

  test "clearing the filter wipes the remembered one so it is not replayed" do
    event(title: "JazzNightShow", genre_list: ["Jazzy"], start_date: Date.current + 2.days)

    get events_path(filtered: 1, g: ["Jazzy"])
    follow_redirect!

    get events_path(filtered: 1)
    assert_redirected_to events_path
    follow_redirect!
    assert_response :success

    get events_path
    assert_response :success
  end

  test "the feed ships the prefetch opt-out, and a chip's href would otherwise store a filter" do
    event(title: "JazzNightShow", genre_list: ["Jazzy"], start_date: Date.current + 2.days)

    get events_path

    assert_select "head meta[name=turbo-prefetch][content=?]", "false"
    assert_select "a.filter-link[href=?]", events_path(g: ["Jazzy"], filtered: 1), text: "Jazzy"

    get events_path(g: ["Jazzy"], filtered: 1)
    follow_redirect!
    get events_path
    assert_redirected_to events_path(g: ["Jazzy"])
  end

  test "the default date floor hides past events" do
    event(title: "PastShow", start_date: Date.current - 10.days)
    event(title: "FutureShow", start_date: Date.current + 10.days)

    get events_path

    assert_includes response.body, "FutureShow"
    refute_includes response.body, "PastShow"
  end

  test "the admin delete button dismisses (soft-delete): gone from public, kept in DB" do
    e = event(title: "DismissMeShow", start_date: Date.current + 3.days)
    sign_in_as user(admin: true)

    delete event_path(e)
    assert_redirected_to events_path

    assert e.reload.dismissed?, "event should be soft-deleted, not destroyed"
    assert Event.exists?(e.id), "row should remain in the DB"

    get events_path
    assert_not_includes @response.body, "DismissMeShow"
  end

  test "non-admins cannot dismiss events" do
    e = event(title: "KeepMeShow", start_date: Date.current + 3.days)
    sign_in_as user(admin: false)

    delete event_path(e)
    assert_response :forbidden
    refute e.reload.dismissed?
  end

  test "the edit gear links to the admin event page, only for admins" do
    e = event(start_date: Date.current + 3.days)

    sign_in_as user(admin: true)
    get events_path
    assert_select "a.icon-button[href=?]", admin_event_path(e)

    sign_in_as user(admin: false)
    get events_path
    assert_select "a.icon-button", count: 0
  end

  test "the delete button submits a real DELETE (method override present)" do
    e = event(start_date: Date.current + 3.days)
    sign_in_as user(admin: true)

    get events_path
    assert_select "form[action=?][method=post]", event_path(e) do
      assert_select "input[type=hidden][name=_method][value=delete]"
    end
  end
end
