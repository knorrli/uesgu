require 'db_test_helper'

# Every admin browse page offers a way back toward the admin start page:
# index/queue pages link straight to the dashboard, and a detail page links to
# its own list (which itself links home).
class AdminBackNavTest < ActionDispatch::IntegrationTest
  test 'admin browse pages link back to the dashboard' do
    sign_in_as user(admin: true)

    [genres_path, queue_genres_path, admin_users_path, admin_invitations_path].each do |path|
      get path
      assert_response :success, "#{path} renders"
      assert_select 'a[href=?]', admin_path, { minimum: 1 }, "#{path} links back to /admin"
    end
  end

  test 'a user detail page links back to the accounts list' do
    member = user
    sign_in_as user(admin: true)

    get admin_user_path(member)
    assert_response :success
    assert_select 'a[href=?]', admin_users_path, { minimum: 1 }, 'show links back to the accounts list'
  end
end
