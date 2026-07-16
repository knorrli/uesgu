require "db_test_helper"

# Locks the reframed web flow: the landing "Notify me" button (shown for any
# signed-in user — an empty filter saves as the notify-on-everything rule), the
# new-alert page (filter carried through + sync checkbox when it matches
# favorites), create from filter params, the read-only list, and
# fire/toggle/destroy. Email channel stays off.
class SavedFiltersTest < ActionDispatch::IntegrationTest
  # --- landing-page button ---------------------------------------------------

  test "the save action shows for a signed-in user, empty filter included" do
    sign_in_as user

    # An empty filter still offers to save — it's the notify-on-everything rule.
    get events_path
    assert_select "a.filter-menu__save"

    get events_path(g: ["Rock"])
    assert_select "a.filter-menu__save"
  end

  # --- saved-filters menu (events feed chip row) -----------------------------

  test "the saved-filters menu lets you apply a saved filter via its full URL" do
    u = sign_in_as user
    r = u.saved_filters.new(cadence: "daily", time_of_day: 540)
    r.filter_attributes = { g: ["Rock"], l: ["Bern"] }
    r.save!

    get events_path
    assert_response :success
    assert_select "details.filter-menu"
    # The apply item links to the full events URL for that filter (shareable; the
    # same target as the /saved_filters "Apply" link).
    assert_select "a.filter-menu__apply[href=?]",
                  events_path(q: [], g: ["Rock"], l: ["Bern"], d: [])
  end

  test "the saved-filters menu shows for any signed-in user, but never when signed out" do
    sign_in_as user
    get events_path
    assert_select "details.filter-menu", true, "menu shows on an empty feed (save-everything)"

    reset! # drop the session → signed out
    get events_path
    assert_select "details.filter-menu", false, "no menu for anonymous visitors"
  end

  # --- new -------------------------------------------------------------------

  test "new requires authentication" do
    get new_saved_filter_path
    assert_redirected_to new_session_path
  end

  test "new (added filter) carries the filter through and wires the schedule form" do
    sign_in_as user
    leaf = genre_in_tree("Zylonew")
    get new_saved_filter_path(g: [leaf.name]) # no date → added rule

    assert_response :success
    # The picked genre is pre-checked in the What tree; the window is the When panel.
    assert_select "input[name='g[]'][value='#{leaf.name}'][checked]"
    assert_select 'form[data-controller~="saved-filter-form"]'
    assert_select 'select[name="saved_filter[cadence]"][data-saved-filter-form-target="cadence"]'
    assert_select '[data-saved-filter-form-target="weekday"]'
    # No name field — the name is the derived filter description, in the title.
    assert_select 'input[name="saved_filter[name]"]', false
    assert_select "h1", text: /Zylonew/
  end

  test "new (windowed filter) preselects the window and shows the firing-day picker" do
    sign_in_as user
    get new_saved_filter_path(l: ["Bern"], d: ["this_weekend"]) # weekly window

    assert_response :success
    assert_select "section.sheet[data-field='when'] input[name='d[]'][value='this_weekend'][checked]"
    # The cadence picker is always in the DOM (hidden client-side when windowed);
    # the firing-day picker is present for the weekly rhythm.
    assert_select 'select[name="saved_filter[weekday]"]'
  end

  test "new with a multi-window filter (carried from the feed) narrows to one window" do
    sign_in_as user
    get new_saved_filter_path(d: %w[tomorrow this_weekend next_week])

    assert_response :success
    # Single-select: only the first window is pre-checked, the others are not.
    assert_select "section.sheet[data-field='when'] input[name='d[]'][value='tomorrow'][checked]"
    assert_select "section.sheet[data-field='when'] input[name='d[]'][value='this_weekend'][checked]", false
    assert_select "section.sheet[data-field='when'] input[name='d[]'][value='next_week'][checked]", false
    # The trigger badge reflects one window, not three.
    assert_select ".filter-trigger[data-filter-sheets-field-param='when'] .badge", text: "1"
  end

  # --- create ----------------------------------------------------------------

  test "create saves the drafted filter and returns to the list" do
    u = sign_in_as user

    assert_difference -> { u.saved_filters.count }, 1 do
      post saved_filters_path, params: {
        saved_filter: { name: "Bern weekends", cadence: "weekly", weekday: "5",
                             time_string: "17:30", notify_push: "1", notify_email: "0" },
        l: ["Bern"], d: ["this_weekend"]
      }
    end

    r = u.saved_filters.last
    assert_redirected_to saved_filters_path # explicit Save → the Saved-filters list
    assert_equal 1050, r.time_of_day
    assert_equal ["Bern"], r.location_list
    assert_equal ["this_weekend"], r.date_ranges
    assert r.happening?
  end

  test "create uses safe defaults — in-app on, push/email off" do
    u = sign_in_as user

    # A draft saved with only the filter (no channel params) lands on the in-app
    # channel only — notifying by default, but nothing intrusive.
    assert_difference -> { u.saved_filters.count }, 1 do
      post saved_filters_path, params: { q: ["Rock"] }
    end

    r = u.saved_filters.last
    assert_redirected_to saved_filters_path
    assert r.notify_in_app?
    refute r.notify_push?
    refute r.notify_email?
  end

  test "create accepts an empty filter as the notify-on-everything rule" do
    u = sign_in_as user
    assert_difference -> { u.saved_filters.count }, 1 do
      post saved_filters_path, params: { saved_filter: { cadence: "daily", time_string: "09:00" } }
    end
    assert_redirected_to saved_filters_path
    r = u.saved_filters.last
    assert_empty r.queries + r.genres + r.location_list + r.date_ranges, "no criteria => all events"
  end

  # --- one rule per filter set -----------------------------------------------

  test "create on a filter that already has a rule lands on the existing one, no duplicate" do
    u = sign_in_as user
    existing = u.saved_filters.new(name: "x", cadence: "daily", time_of_day: 540)
    existing.filter_attributes = { q: ["Rock"], l: ["Bern"] }
    existing.save!

    # Same filter set, order flipped → still the same rule.
    assert_no_difference -> { u.saved_filters.count } do
      post saved_filters_path, params: { l: ["Bern"], q: ["Rock"] }
    end
    assert_redirected_to edit_saved_filter_path(existing)
  end

  test "the save control is a single menu item: draft link when unsaved, edit link when saved" do
    u = sign_in_as user

    # Unsaved: the menu's save item drafts a new saved filter from this filter.
    get events_path(g: ["Rock"])
    assert_select "a.filter-menu__save[href=?]", new_saved_filter_path(g: ["Rock"])
    assert_select "a.filter-menu__save.is-saved", false

    # Saved (any kind): the active filter is now a saved one — the item links to its
    # editor and the menu toggle shows the filled-funnel saved cue.
    r = u.saved_filters.new(name: "x", cadence: "daily", time_of_day: 540)
    r.filter_attributes = { g: ["Rock"] }
    r.save!
    get events_path(g: ["Rock"])
    assert_select "a.filter-menu__save.is-saved[href=?]", edit_saved_filter_path(r)
    assert_select ".filter-menu__toggle .funnel-fill"
    # No separate notify control on the events page.
    assert_select "a.notify-bell-link", false
  end

  # --- edit / update ---------------------------------------------------------

  test "edit shows the schedule + the saved filter pre-checked in the tree" do
    u = sign_in_as user
    leaf = genre_in_tree("Zyloedit")
    r = u.saved_filters.new(name: "My alert", cadence: "weekly", weekday: 5, time_of_day: 1050)
    r.filter_attributes = { g: [leaf.name] }
    r.save!

    get edit_saved_filter_path(r)
    assert_response :success
    # The saved genre is pre-checked in the What tree; the window is the When panel.
    assert_select "input[name='g[]'][value='#{leaf.name}'][checked]"
    assert_select "section.sheet[data-field='when'] input[name='d[]']"
    # No name field; the derived name is the (server-rendered) page title.
    assert_select 'input[name="saved_filter[name]"]', false
    assert_select "h1", text: /Zyloedit/
  end

  test "update saves genre picks and free-text queries from the what field" do
    u = sign_in_as user
    r = u.saved_filters.new(cadence: "daily", time_of_day: 60)
    r.filter_attributes = { g: ["Rock"] }
    r.save!

    # The What tree submits genre picks as g[] and free text as q[].
    patch saved_filter_path(r), params: {
      saved_filter: { cadence: "daily", time_string: "09:00" },
      g: %w[Rock Jazz], q: ["Radiohead"], l: [""], d: [""]
    }

    assert_redirected_to saved_filters_path # explicit save returns to the list
    r.reload
    assert_equal %w[Rock Jazz], r.genres
    assert_equal ["Radiohead"], r.queries
  end

  test "editing a filter to collide with another is rejected, with a link to it" do
    u = sign_in_as user
    a = u.saved_filters.new(name: "a", cadence: "daily", time_of_day: 540)
    a.filter_attributes = { g: ["Rock"] }
    a.save!
    b = u.saved_filters.new(name: "b", cadence: "daily", time_of_day: 540)
    b.filter_attributes = { g: ["Jazz"] }
    b.save!

    # Editing B's scope to match A is now blocked (duplicate fingerprints break the
    # events-page "saved?" match) — not applied, re-renders the editor.
    patch saved_filter_path(b), params: { g: ["Rock"], l: [""], d: [""] }
    assert_response :unprocessable_entity
    assert_equal ["Jazz"], b.reload.genres # unchanged
    # The re-rendered editor surfaces the heads-up linking to A.
    assert_select ".saved-filter-notice a[href=?]", edit_saved_filter_path(a)
  end

  test "editing only the schedule saves and returns to the list" do
    u = sign_in_as user
    r = u.saved_filters.new(name: "r", cadence: "daily", time_of_day: 540)
    r.filter_attributes = { g: ["Rock"] }
    r.save!

    patch saved_filter_path(r), params: {
      saved_filter: { cadence: "daily", time_string: "20:00" }, g: ["Rock"], l: [""], d: [""]
    }

    assert_redirected_to saved_filters_path
    assert_equal 1200, r.reload.time_of_day
  end

  test "update changes the schedule + channels without touching the filter" do
    u = sign_in_as user
    r = u.saved_filters.new(cadence: "weekly", weekday: 5, time_of_day: 1050, notify_email: false)
    r.filter_attributes = { g: ["Rock"] }
    r.save!

    patch saved_filter_path(r), params: {
      saved_filter: { cadence: "weekly", weekday: "2", time_string: "08:15", notify_push: "1", notify_email: "1" },
      g: ["Rock"]
    }

    assert_redirected_to saved_filters_path
    r.reload
    assert_equal 2, r.weekday
    assert_equal 495, r.time_of_day
    assert r.notify_email?
    assert_equal ["Rock"], r.genres # filter untouched
  end

  test "update with a windowed filter flips an added rule to happening" do
    u = sign_in_as user
    r = u.saved_filters.new(cadence: "weekly", weekday: 5, time_of_day: 1050)
    r.filter_attributes = { g: ["Rock"] } # no date → added
    r.save!
    assert r.added?

    # Selecting a window in the form flips the rule to happening.
    patch saved_filter_path(r), params: {
      saved_filter: { cadence: "weekly", weekday: "5", time_string: "17:30" },
      g: ["Rock"], d: ["this_weekend"]
    }

    assert_redirected_to saved_filters_path
    r.reload
    assert_equal ["this_weekend"], r.date_ranges
    assert r.happening?
  end

  test "edit only reaches the current user's own rules" do
    other = User.create!(username: "someone", password: "password12345")
    foreign = other.saved_filters.new(cadence: "daily", time_of_day: 60)
    foreign.filter_attributes = { g: ["Rock"] }
    foreign.save!

    sign_in_as user
    get edit_saved_filter_path(foreign)
    assert_response :not_found
  end

  # --- list + management -----------------------------------------------------

  test "index lists alerts read-only with their summary and actions" do
    u = sign_in_as user
    r = u.saved_filters.new(cadence: "weekly", weekday: 5, time_of_day: 1050)
    r.filter_attributes = { l: ["Dachstock"], d: ["this_weekend"] }
    r.save!

    get saved_filters_path
    assert_response :success
    # The name is the derived filter description (no custom names), and the name
    # itself is the link to the editor (no separate Bearbeiten button in the row).
    assert_select ".saved-filter-card .saved-filter-card__name", /Dachstock/
    assert_select ".saved-filter-card__actions form" # fire/toggle/delete
    assert_select "a.saved-filter-card__name[href=?]", edit_saved_filter_path(r)
  end

  test "fire now creates an in-app notification when there are matches" do
    u = sign_in_as user
    event(created_at: 1.hour.ago, start_date: Date.current + 3, genre_list: ["Rock"])
    r = u.saved_filters.new(cadence: "daily", time_of_day: 1, notify_push: false, notify_email: false)
    r.filter_attributes = { q: ["Rock"] }
    r.save!
    r.update_column(:last_fired_at, 2.hours.ago)

    assert_difference -> { u.notifications.count }, 1 do
      post fire_saved_filter_path(r)
    end
    assert_redirected_to notification_path(u.notifications.last) # lands on the digest
  end

  test "fire with no matches stays on the list with an empty notice" do
    u = sign_in_as user
    r = u.saved_filters.new(cadence: "daily", time_of_day: 1, notify_push: false)
    r.filter_attributes = { q: ["nothing-matches-this"] }
    r.save!

    assert_no_difference -> { u.notifications.count } do
      post fire_saved_filter_path(r)
    end
    assert_redirected_to saved_filters_path
  end

  test "editing in-app off makes a saved filter silent (and forces other channels off)" do
    u = sign_in_as user
    r = u.saved_filters.new(cadence: "daily", time_of_day: 1, notify_push: true)
    r.filter_attributes = { q: ["Rock"] }
    r.save!
    assert r.notifying?

    patch saved_filter_path(r), params: {
      saved_filter: { cadence: "daily", time_string: "09:00", notify_in_app: "0", notify_push: "1" },
      q: ["Rock"]
    }
    r.reload
    refute r.notifying?, "in-app off → silent saved filter"
    refute r.notify_push?, "push is forced off without in-app"
  end

  test "destroy removes a saved filter" do
    u = sign_in_as user
    r = u.saved_filters.new(cadence: "daily", time_of_day: 1)
    r.filter_attributes = { q: ["Rock"] }
    r.save!

    assert_difference -> { u.saved_filters.count }, -1 do
      delete saved_filter_path(r)
    end
  end

  private

  # A genre that actually renders in the editor's What tree: a root (no events) with
  # one in-use child, so genre_filter_tree includes it and the child is checkable.
  # Returns the child (the leaf you filter by).
  def genre_in_tree(name)
    root = genre(name: "#{name}root", events_count: 0)
    leaf = genre(name: name, events_count: 1)
    leaf.set_parent!(root)
    leaf
  end
end
