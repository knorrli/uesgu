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

  test "an admin toggles the contributor capability on and off" do
    member = user(username: "capturer")
    sign_in_as user(admin: true)

    patch toggle_contributor_admin_user_path(member)
    assert_redirected_to admin_user_path(member)
    assert_predicate member.reload, :contributor?

    patch toggle_contributor_admin_user_path(member)
    refute_predicate member.reload, :contributor?
  end

  test "a non-admin cannot grant themselves the contributor capability" do
    member = user(admin: false)
    sign_in_as member

    patch toggle_contributor_admin_user_path(member)
    assert_response :forbidden
    refute_predicate member.reload, :contributor?
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
