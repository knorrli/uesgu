require "db_test_helper"

class AdminUsersTest < ActionDispatch::IntegrationTest
  test "guests are sent to login, non-admins are forbidden" do
    get admin_users_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get admin_users_path
    assert_response :forbidden
  end

  test "an admin can list and inspect accounts" do
    member = user(username: "memberx")
    sign_in_as user(admin: true)

    get admin_users_path
    assert_response :success
    assert_select "a", text: "memberx"

    get admin_user_path(member)
    assert_response :success
  end

  test "the account page shows how an invited user joined" do
    inviter = user(username: "inviter", admin: true)
    invite = invitation(created_by: inviter)
    joiner = user(username: "joiner")
    invite.redeem!(joiner)
    sign_in_as user(admin: true)

    get admin_user_path(joiner)
    assert_response :success
    assert_select "body", text: /inviter/
    assert_select "body", text: /#{invite.formatted_code}/
  end

  test "an admin grants and revokes permissions, and each change is logged" do
    member = user(username: "zorpmod")
    sign_in_as user(admin: true)

    get admin_user_path(member)
    User::PERMISSIONS.each { |permission| assert_select "input[type=checkbox][value=?]", permission }

    patch permissions_admin_user_path(member), params: { user: { permissions: ["", "genres", "capture"] } }
    assert_redirected_to admin_user_path(member)
    assert_equal %w[genres capture], member.reload.permissions

    patch permissions_admin_user_path(member), params: { user: { permissions: ["", "genres"] } }
    assert_equal %w[genres], member.reload.permissions

    assert_equal [%w[user.grant_permission genres], %w[user.grant_permission capture], %w[user.revoke_permission capture]],
                 ActionLog.order(:id).map { |entry| [entry.action, entry.details["permission"]] }
  end

  test "only an admin can grant permissions, even to themselves" do
    member = user(permissions: %w[curate_events genres places capture invite])
    sign_in_as member

    patch permissions_admin_user_path(member), params: { user: { permissions: %w[genres] } }
    assert_response :forbidden
    assert_equal 5, member.reload.permissions.size
  end

  test "an admin can delete a spam account" do
    spam = user(username: "spammer")
    sign_in_as user(admin: true)

    assert_difference -> { User.count }, -1 do
      delete admin_user_path(spam)
    end
    assert_redirected_to admin_users_path
    assert_nil User.find_by(username: "spammer")
  end

  test "an account page lists the events that account captured" do
    contributor = user(username: "zorpfan", permissions: %w[capture])
    event(title: "Captured Show", url: nil, data_source: EventCapture::Creator::DATA_SOURCE,
          captured_by: contributor)
    event(title: "Someone Else's Show")
    sign_in_as user(admin: true)

    get admin_user_path(contributor)
    assert_select "a[href=?]", admin_event_path(Event.find_by!(title: "Captured Show")), text: "Captured Show"
    assert_select "a", text: "Someone Else's Show", count: 0
  end

  test "deleting an account keeps the events it captured" do
    spam = user(username: "spammer", permissions: %w[capture])
    captured = event(title: "Captured Show", url: nil, data_source: EventCapture::Creator::DATA_SOURCE,
                     captured_by: spam)
    sign_in_as user(admin: true)

    delete admin_user_path(spam)
    assert_nil captured.reload.captured_by
  end

  test "an admin cannot delete their own account here" do
    admin = user(admin: true)
    sign_in_as admin

    assert_no_difference -> { User.count } do
      delete admin_user_path(admin)
    end
    assert_redirected_to admin_users_path
    assert User.exists?(admin.id)
  end
end
