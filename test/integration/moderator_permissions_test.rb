require "db_test_helper"

class ModeratorPermissionsTest < ActionDispatch::IntegrationTest
  ADMIN_ONLY_PATHS = %i[admin_users_path admin_scrape_runs_path admin_scraper_coverage_path admin_venue_leads_path
                        admin_extraction_attempts_path admin_discard_rules_path styleguide_path].freeze

  test "a curator reaches the event pages and the feed's actions, and nothing else" do
    show = event(title: "Zorp Night", start_date: Date.current + 3)
    sign_in_as user(permissions: %w[curate_events])

    get admin_path
    assert_response :success
    assert_select "a[href=?]", admin_events_path
    assert_select "a[href=?]", admin_action_logs_path
    assert_select "a[href=?]", genres_path, count: 0
    assert_select "a[href=?]", admin_localities_path, count: 0
    assert_select "a[href=?]", admin_users_path, count: 0

    get admin_events_path
    assert_response :success
    get admin_event_path(show)
    assert_response :success

    get events_path
    assert_select "form[action=?] button.danger", event_path(show)

    [genres_path, admin_localities_path, admin_places_path, admin_invitations_path, capture_path].each do |path|
      get path
      assert_response :forbidden, path
    end
    ADMIN_ONLY_PATHS.each do |path|
      get public_send(path)
      assert_response :forbidden, path
    end
  end

  test "a moderator sees and undoes only the log entries of their own areas" do
    show = event(title: "Zorp Night")
    genre = genre(name: "zorpwave")
    admin = user(admin: true)
    removal = ActionLog.track("event.dismiss", show, user: admin) { show.dismiss! }
    ActionLog.track("genre.hide", genre, user: admin) { genre.hide! }
    ActionLog.record!("user.delete", user(username: "zorpgone"), user: admin)
    sign_in_as user(permissions: %w[curate_events])

    get admin_action_logs_path
    assert_select ".event-row", count: 1
    assert_select "a[href=?]", admin_event_path(show)

    post undo_admin_action_log_path(removal)
    refute_predicate show.reload, :dismissed?

    hide = ActionLog.find_by!(action: "genre.hide")
    post undo_admin_action_log_path(hide)
    assert_response :not_found
  end

  test "someone who may only capture gets capture, but not the admin" do
    sign_in_as user(permissions: %w[capture])

    get capture_path
    assert_response :success
    get admin_path
    assert_response :forbidden
  end

  test "an inviter sees and revokes only their own invitations" do
    inviter = user(permissions: %w[invite])
    theirs = invitation(created_by: inviter)
    others = invitation(created_by: user(admin: true))
    sign_in_as inviter

    get admin_invitations_path
    assert_response :success
    assert_select "*", text: /#{theirs.formatted_code}/
    assert_no_match others.formatted_code, response.body

    delete admin_invitation_path(others)
    assert_response :not_found
    assert Invitation.exists?(others.id)
  end

  test "genre editing from the feed follows the genres permission" do
    genre = genre(name: "zorpwave")
    event(start_date: Date.current + 3, genre_list: [genre.name])
    sign_in_as user(permissions: %w[genres])

    get events_path
    assert_select "a[href=?]", edit_tag_path(ActsAsTaggableOn::Tag.find_by!(name: genre.name))
    get genres_path
    assert_response :success
    get admin_events_path
    assert_response :forbidden
  end
end
