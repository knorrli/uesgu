require "db_test_helper"

# Back navigation follows one rule: every page's back link points *up* one level,
# and the top of the tree is the main events feed. Assertions target the
# `.back-link` element specifically (not the nav menu, which links to /admin on
# every admin page regardless).
class AdminBackNavTest < ActionDispatch::IntegrationTest
  test "admin catalogue index pages link back to the dashboard" do
    sign_in_as user(admin: true)

    [genres_path, admin_users_path, admin_invitations_path].each do |path|
      get path
      assert_response :success, "#{path} renders"
      assert_select "a.back-link[href=?]", admin_path, { minimum: 1 }, "#{path} back link → /admin"
    end
  end

  test "the genre tree and queue link back to the genres list, not the dashboard" do
    sign_in_as user(admin: true)

    [tree_genres_path, queue_genres_path].each do |path|
      get path
      assert_response :success, "#{path} renders"
      assert_select "a.back-link[href=?]", genres_path, { minimum: 1 }, "#{path} back link → genres list"
    end
  end

  test "a user detail page links back to the accounts list" do
    member = user
    sign_in_as user(admin: true)

    get admin_user_path(member)
    assert_response :success
    assert_select "a.back-link[href=?]", admin_users_path, { minimum: 1 }, "show back link → accounts list"
  end

  test "the admin dashboard links back to the main events feed" do
    sign_in_as user(admin: true)

    get admin_path
    assert_response :success
    assert_select "a.back-link[href=?]", root_path, { minimum: 1 }, "dashboard back link → events feed"
  end
end
