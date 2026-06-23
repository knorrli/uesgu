require "db_test_helper"

# Locks User's normalizations, validation rules, and the notification-interval
# lookup. No taxonomy involved — pure account mechanics.
class UserTest < ActiveSupport::TestCase
  test "username is normalized to stripped lowercase" do
    u = user(username: "  FooBar  ")
    assert_equal "foobar", u.username
  end

  test "email_address is normalized; blank becomes nil" do
    assert_equal "foo@bar.com", user(email_address: " Foo@Bar.COM ").email_address
    assert_nil user(email_address: "   ").email_address
  end

  test "username uniqueness is case-insensitive via normalization" do
    user(username: "taken")
    dup = User.new(username: "TAKEN", password: "secret123")
    refute dup.valid?
    assert_predicate dup.errors[:username], :any?, "a normalized-duplicate username is rejected"
  end

  test "username must match the allowed character format" do
    bad = User.new(username: "has space", password: "secret123")
    refute bad.valid?
    assert_predicate bad.errors[:username], :any?
  end

  test "username length is bounded to 2..30" do
    refute User.new(username: "a", password: "secret123").valid?
    refute User.new(username: "x" * 31, password: "secret123").valid?
  end

  test "two users may both have no email" do
    user(email_address: nil)
    assert user(email_address: nil).valid?
  end

  test "locale must be an available locale but may be blank" do
    assert user(locale: "").valid?
    refute User.new(username: "loc", password: "secret123", locale: "xx").valid?
  end

  test "events_view must be list or calendar, or nil" do
    assert user(events_view: "calendar").valid?
    refute User.new(username: "ev", password: "secret123", events_view: "grid").valid?
  end

  test "admin? reflects the admin flag" do
    refute user.admin?
    assert user(admin: true).admin?
  end
end
