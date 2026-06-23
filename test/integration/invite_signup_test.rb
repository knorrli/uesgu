require "db_test_helper"

# The invitation gate over the real HTTP signup flow: no account is ever created
# without a valid, unspent code, and a code lets exactly one account through.
class InviteSignupTest < ActionDispatch::IntegrationTest
  test "signup is refused with no code" do
    assert_no_difference -> { User.count } do
      post registration_path, params: { user: signup_user }
    end
    assert_response :unprocessable_entity
  end

  test "signup is refused with an unknown code" do
    assert_no_difference -> { User.count } do
      post registration_path, params: { invitation_code: "ZZZZ9999", user: signup_user }
    end
    assert_response :unprocessable_entity
  end

  test "signup is refused with an expired code" do
    invite = invitation(expires_at: 1.hour.ago)
    assert_no_difference -> { User.count } do
      post registration_path, params: { invitation_code: invite.code, user: signup_user }
    end
    assert_response :unprocessable_entity
  end

  test "a valid code lets exactly one account through, then is spent" do
    invite = invitation

    assert_difference -> { User.count }, 1 do
      post registration_path, params: { invitation_code: invite.code, user: signup_user("first") }
    end
    assert_redirected_to root_path
    assert_equal "first", invite.reload.redeemed_by.username

    # The now-spent code cannot create a second account.
    delete session_path
    assert_no_difference -> { User.count } do
      post registration_path, params: { invitation_code: invite.code, user: signup_user("second") }
    end
    assert_response :unprocessable_entity
  end

  test "the code tolerates the formatted (dashed, lower-case) form a friend might paste" do
    invite = invitation

    assert_difference -> { User.count }, 1 do
      post registration_path, params: { invitation_code: invite.formatted_code.downcase, user: signup_user }
    end
    assert_redirected_to root_path
  end

  test "the shareable signup link prefills the code field" do
    invite = invitation
    get signup_path(invite: invite.code)
    assert_response :success
    assert_select "input[name=invitation_code][value=?]", invite.code
  end

  private

  def signup_user(name = "newbie")
    { username: name, password: PASSWORD, password_confirmation: PASSWORD }
  end
end
