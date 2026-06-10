require 'db_test_helper'

# Locks the account lifecycle through the real HTTP stack: registration (which
# logs the new user straight in, without forcing favorites), login success and
# failure, logout, and the redirect that guards authenticated pages.
class AuthenticationFlowTest < ActionDispatch::IntegrationTest
  test 'registration creates an account, signs in, and lands on root' do
    assert_difference -> { User.count }, 1 do
      post registration_path, params: {
        user: { username: 'newcomer', password: PASSWORD, password_confirmation: PASSWORD }
      }
    end
    assert_redirected_to root_path

    created = User.find_by(username: 'newcomer')
    assert_empty created.location_list, 'onboarding must not force favorites'
    assert_empty created.style_list

    # The session cookie is live: a protected page now renders.
    get settings_path
    assert_response :success
  end

  test 'registration with mismatched confirmation re-renders the form' do
    assert_no_difference -> { User.count } do
      post registration_path, params: {
        user: { username: 'oops', password: PASSWORD, password_confirmation: 'different' }
      }
    end
    assert_response :unprocessable_entity
  end

  test 'login with valid credentials starts a session' do
    u = user
    post session_path, params: { username: u.username, password: PASSWORD }
    assert_redirected_to root_url

    get settings_path
    assert_response :success
  end

  test 'login with bad credentials is rejected back to the form' do
    u = user
    post session_path, params: { username: u.username, password: 'wrong' }
    assert_redirected_to new_session_path

    get settings_path
    assert_redirected_to new_session_path, 'still unauthenticated'
  end

  test 'logout terminates the session' do
    sign_in_as user
    delete session_path
    assert_redirected_to root_path

    get settings_path
    assert_redirected_to new_session_path
  end

  test 'an unauthenticated request to a protected page redirects to login' do
    get settings_path
    assert_redirected_to new_session_path
  end
end
