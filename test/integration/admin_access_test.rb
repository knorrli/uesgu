require 'db_test_helper'

# Locks the admin gate: require_authentication then require_admin. Curation
# endpoints (admin dashboard, genre dispositions) must be unreachable by guests
# and non-admins, and the genre return_to must resist open redirects.
class AdminAccessTest < ActionDispatch::IntegrationTest
  test 'guests are sent to login, non-admins are forbidden, admins get in' do
    get admin_path
    assert_redirected_to new_session_path, 'guest -> login'

    sign_in_as user(admin: false)
    get admin_path
    assert_response :forbidden, 'authenticated non-admin -> 403'

    delete session_path
    sign_in_as user(admin: true)
    get admin_path
    assert_response :success, 'admin -> dashboard'
  end

  test 'a non-admin cannot disposition a genre' do
    g = genre(events_count: 1)
    sign_in_as user(admin: false)

    post ignore_genre_path(g)

    assert_response :forbidden
    refute g.reload.ignored?
  end

  test 'an admin can ignore a genre via the endpoint' do
    g = genre(events_count: 1)
    sign_in_as user(admin: true)

    post ignore_genre_path(g), params: { return_to: genres_path }

    assert g.reload.ignored?
  end

  test 'genre return_to refuses an external open-redirect target' do
    g = genre(events_count: 1)
    sign_in_as user(admin: true)

    post ignore_genre_path(g), params: { return_to: 'http://evil.example.com/phish' }

    assert_redirected_to genres_path, 'off-site return_to is ignored'
  end
end
