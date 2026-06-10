require 'db_test_helper'

# The invite gate is üsgu's anti-bot defence, so the code must be unguessable,
# unambiguous to read, and — critically — spendable exactly once.
class InvitationTest < ActiveSupport::TestCase
  test 'generates an unambiguous fixed-length code on create' do
    inv = invitation
    assert_match(/\A[#{Invitation::CODE_ALPHABET}]{#{Invitation::CODE_LENGTH}}\z/, inv.code)
  end

  test 'normalize_code strips formatting and upcases' do
    assert_equal 'ABCD2345', Invitation.normalize_code('  abcd-2345 ')
  end

  test 'available_by_code matches an available code regardless of formatting' do
    inv = invitation
    assert_equal inv, Invitation.available_by_code(inv.formatted_code.downcase)
    assert_nil Invitation.available_by_code('does-not-exist')
    assert_nil Invitation.available_by_code('')
  end

  test 'redeem! spends the code exactly once' do
    inv = invitation
    member = user

    inv.redeem!(member)

    assert inv.reload.redeemed?
    assert_equal member, inv.redeemed_by
    assert_not_nil inv.redeemed_at
    refute inv.available?
    assert_raises(Invitation::Unavailable) { inv.redeem!(user) }
  end

  test 'an expired code is neither available nor redeemable' do
    inv = invitation(expires_at: 1.hour.ago)

    refute inv.available?
    assert inv.expired?
    assert_nil Invitation.available_by_code(inv.code)
    assert_raises(Invitation::Unavailable) { inv.redeem!(user) }
  end

  test 'scopes partition codes by state' do
    available = invitation
    redeemed = invitation.tap { |i| i.redeem!(user) }
    expired = invitation(expires_at: 1.hour.ago)

    assert_includes Invitation.available, available
    assert_includes Invitation.redeemed, redeemed
    assert_includes Invitation.expired, expired

    refute_includes Invitation.available, redeemed
    refute_includes Invitation.available, expired
  end

  test 'formatted_code groups the raw code into fours' do
    inv = invitation
    assert_equal "#{inv.code[0, 4]}-#{inv.code[4, 4]}", inv.formatted_code
  end

  test 'deleting the redeeming user keeps the spent code as an orphaned record' do
    inv = invitation
    member = user
    inv.redeem!(member)

    member.destroy

    assert inv.reload.redeemed?, 'still counts as spent'
    assert_nil inv.redeemed_by_id, 'just unlinked from the deleted account'
  end

  test 'deleting the minting admin removes their unspent codes' do
    admin = user(admin: true)
    inv = invitation(created_by: admin)

    admin.destroy

    assert_nil Invitation.find_by(id: inv.id)
  end
end
