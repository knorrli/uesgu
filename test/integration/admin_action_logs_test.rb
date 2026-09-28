require "db_test_helper"

class AdminActionLogsTest < ActionDispatch::IntegrationTest
  test "guests are sent to login, non-admins are forbidden" do
    get admin_action_logs_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get admin_action_logs_path
    assert_response :forbidden
  end

  test "removing an event from the feed is logged with who did it" do
    admin = user(admin: true, username: "zorpadmin")
    show = event(title: "Zorp Night")
    sign_in_as admin

    delete event_path(show)

    entry = ActionLog.last
    assert_equal ["event.dismiss", admin, show], [entry.action, entry.user, entry.subject]
  end

  test "every event action in the admin is logged" do
    show = event(title: "Wrong Title")
    canonical = event(title: "Canonical Show")
    sign_in_as user(admin: true)

    patch admin_event_path(show), params: { event: { title: "Right Title", date: show.start_date.iso8601 } }
    patch revert_admin_event_path(show, field: "title")
    delete admin_event_path(show)
    patch undismiss_admin_event_path(show)
    patch merge_admin_event_path(show), params: { canonical_id: canonical.id }
    patch unmerge_admin_event_path(show)

    assert_equal %w[event.edit event.revert event.dismiss event.restore event.merge event.unmerge],
                 ActionLog.order(:id).pluck(:action)
  end

  test "a merge names the event it went into" do
    show = event(title: "Zorp Night (copy)")
    canonical = event(title: "Zorp Night")
    sign_in_as user(admin: true)
    patch merge_admin_event_path(show), params: { canonical_id: canonical.id }

    get admin_action_logs_path
    assert_select ".event-row__main", text: /Zorp Night \(copy\).*Zorp Night/
  end

  test "the log lists an action with an undo that restores the event" do
    show = event(title: "Zorp Night")
    sign_in_as user(admin: true, username: "zorpadmin")
    delete admin_event_path(show)
    entry = ActionLog.last

    get admin_action_logs_path
    assert_select ".event-row", text: /zorpadmin/
    assert_select "a[href=?]", admin_event_path(show), text: "Zorp Night"
    assert_select "form[action=?]", undo_admin_action_log_path(entry)

    post undo_admin_action_log_path(entry)
    assert_redirected_to admin_action_logs_path
    refute_predicate show.reload, :dismissed?

    get admin_action_logs_path
    assert_select "form[action=?]", undo_admin_action_log_path(entry), count: 0
    assert_select ".event-row__meta", text: I18n.t("admin.action_logs.index.undone_by", actor: "zorpadmin")
  end

  test "an action changed since shows who changed it and refuses a stale undo" do
    show = event(title: "Zorp Night")
    sign_in_as user(admin: true, username: "zorpadmin")
    delete admin_event_path(show)
    first = ActionLog.last
    patch undismiss_admin_event_path(show)

    get admin_action_logs_path
    assert_select "form[action=?]", undo_admin_action_log_path(first), count: 0
    assert_select ".event-row__meta", text: I18n.t("admin.action_logs.index.changed_since", actor: "zorpadmin")

    post undo_admin_action_log_path(first)
    assert_redirected_to admin_action_logs_path
    assert_equal I18n.t("admin.action_logs.undo.stale"), flash[:alert]
    refute_predicate show.reload, :dismissed?
  end

  test "non-admins cannot undo" do
    show = event
    entry = ActionLog.track("event.dismiss", show, user: user) { show.dismiss! }
    sign_in_as user(admin: false)

    post undo_admin_action_log_path(entry)
    assert_response :forbidden
    assert_predicate show.reload, :dismissed?
  end

  test "every other admin action is logged, readable in every language, and has no undo" do
    admin = user(admin: true, username: "zorpadmin")
    sign_in_as admin
    wave = genre(name: "zorpwave")
    core = genre(name: "zorpcore")
    stray = genre(name: "zorpstray")
    saal = place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    keller = place(name: "Zorpkeller", locality: "Zorpwil", canton: "BE")
    zorpheim = Locality.create!(name: "Zorpheim")
    zorpville = Locality.create!(name: "Zorpville")
    member = user(username: "zorpmember")

    post set_parent_genre_path(wave), params: { genre: { parent_genre_id: core.id } }
    post set_parent_genre_path(wave), params: { genre: { parent_genre_id: "" } }
    post rename_genre_path(wave), params: { genre: { name: "zorpwaves" } }
    %i[ignore_genre_path hide_genre_path block_genre_path restore_genre_path].each { |path| post public_send(path, wave) }
    post merge_genre_path(stray), params: { genre: { canonical_genre_id: core.id } }
    patch admin_place_path(saal), params: { place: { name: "Zorpsaal Neu", url: "" } }
    patch admin_place_path(saal), params: { place: { name: "Zorpsaal Neu", url: "https://zorpsaal.example" } }
    post merge_admin_place_path(keller), params: { place: { canonical_place_id: saal.id } }
    post unmerge_admin_place_path(keller)
    post merge_admin_locality_path(zorpville), params: { locality: { canonical_locality_id: zorpheim.id } }
    post unmerge_admin_locality_path(zorpville)
    post admin_invitations_path, params: { invitation: { note: "for zorp" } }
    delete admin_invitation_path(Invitation.last)
    2.times { patch toggle_contributor_admin_user_path(member) }
    delete admin_user_path(member)
    Scrapers::Sweep.stub(:enqueue, ->(*, **) { }) { post admin_scrape_runs_path, params: { scraper: "bad_bonn" } }
    post snooze_admin_scrape_runs_path, params: { scraper: "bad_bonn" }
    post wake_admin_scrape_runs_path, params: { scraper: "bad_bonn" }
    post admin_discard_rules_path, params: { discard_rule: { pattern: "zorpquiz" } }
    patch admin_discard_rule_path(DiscardRule.last), params: { discard_rule: { pattern: "zorpquizz" } }
    delete admin_discard_rule_path(DiscardRule.last)

    entries = ActionLog.order(:id)
    assert_equal %w[genre.place genre.make_root genre.rename genre.ignore genre.hide genre.block genre.restore
                    genre.merge place.rename place.edit place.merge place.unmerge locality.merge locality.unmerge
                    invitation.create invitation.revoke user.grant_capture user.revoke_capture user.delete
                    scrape.run scrape.snooze scrape.wake discard_rule.create discard_rule.edit discard_rule.delete],
                 entries.map(&:action)
    assert entries.all? { |entry| entry.user == admin }
    assert entries.none?(&:undoable?)

    %w[en de fr].each do |locale|
      admin.update!(locale: locale)
      get admin_action_logs_path
      assert_response :success
      assert_select "form[action*=undo]", count: 0
    end
  end
end
