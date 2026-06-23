require "db_test_helper"

# Minting and managing invite codes under /admin/invitations: admin-only, and a
# redeemed code stays on the books as an audit record (can't be revoked away).
class AdminInvitationsTest < ActionDispatch::IntegrationTest
  test "guests are sent to login, non-admins are forbidden" do
    get admin_invitations_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get admin_invitations_path
    assert_response :forbidden

    delete session_path
    sign_in_as user(admin: false)
    assert_no_difference -> { Invitation.count } do
      post admin_invitations_path
    end
    assert_response :forbidden
  end

  test "the invitations page renders every code state" do
    available = invitation(note: "for Anna")
    redeemed = invitation.tap { |i| i.redeem!(user(username: "joiner")) }
    expired = invitation(expires_at: 1.hour.ago)
    sign_in_as user(admin: true)

    get admin_invitations_path
    assert_response :success
    assert_select "code.invite__code", text: available.formatted_code
    assert_select "code.invite__code", text: redeemed.formatted_code
    assert_select "code.invite__code", text: expired.formatted_code
    # The shareable link is offered only for the still-usable code, as a
    # copyable field holding the signup URL.
    assert_select ".copy-field input[value=?]", signup_url(invite: available.code), count: 1
  end

  test "invite links served on the umlaut host are minted against the ASCII domain" do
    available = invitation
    # Set the public host before signing in so the session cookie is scoped to it.
    host! "xn--sgu-goa.ch"
    sign_in_as user(admin: true)

    # On the punycode public host, the ugly form would otherwise leak into the
    # copyable link text; share_url_options swaps it for the ASCII twin uesgu.ch
    # (which 301s back, preserving path + query).
    get admin_invitations_path
    assert_response :success
    assert_select ".copy-field input[value*=?]", "://uesgu.ch/", count: 1
    assert_select ".copy-field input[value*=?]", "xn--sgu-goa.ch", count: 0
  end

  test "an admin mints a code, attributed to them" do
    admin = user(admin: true)
    sign_in_as admin

    assert_difference -> { Invitation.count }, 1 do
      post admin_invitations_path, params: { invitation: { note: "for Anna" } }
    end
    assert_redirected_to admin_invitations_path

    created = Invitation.order(:created_at).last
    assert_equal admin, created.created_by
    assert_equal "for Anna", created.note
    assert created.available?
  end

  test "an expiry preset is honoured" do
    sign_in_as user(admin: true)

    post admin_invitations_path, params: { invitation: { expires_in_days: "7" } }

    created = Invitation.order(:created_at).last
    assert_not_nil created.expires_at
    assert created.expires_at > 6.days.from_now
    assert created.expires_at < 8.days.from_now
  end

  test "an admin can revoke an unredeemed code" do
    invite = invitation
    sign_in_as user(admin: true)

    assert_difference -> { Invitation.count }, -1 do
      delete admin_invitation_path(invite)
    end
    assert_redirected_to admin_invitations_path
  end

  test "a redeemed code cannot be revoked" do
    invite = invitation
    invite.redeem!(user)
    sign_in_as user(admin: true)

    assert_no_difference -> { Invitation.count } do
      delete admin_invitation_path(invite)
    end
    assert_redirected_to admin_invitations_path
    assert Invitation.exists?(invite.id)
  end
end
