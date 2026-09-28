require "db_test_helper"

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

  test "a permission is off by default, granted one at a time, and implied by admin" do
    refute user.can?(:capture)
    assert user(admin: true).can?(:genres)

    capturer = user(permissions: %w[capture])
    assert capturer.can?(:capture)
    refute capturer.can?(:curate_events)
  end

  test "only known permissions are kept" do
    assert_equal %w[genres], user(permissions: %w[genres superpowers]).permissions
  end

  test "any permission makes a moderator, who sees the log of their own areas only" do
    refute_predicate user, :moderator?
    refute_predicate user(permissions: %w[capture]), :moderator?

    curator = user(permissions: %w[curate_events capture])
    assert_predicate curator, :moderator?
    assert_equal %w[events], curator.log_areas
    assert_includes user(admin: true).log_areas, "admin"
  end

  test "two users may both have no email" do
    user(email_address: nil)
    assert user(email_address: nil).valid?
  end

  test "locale must be an available locale but may be blank" do
    assert user(locale: "").valid?
    refute User.new(username: "loc", password: "secret123", locale: "xx").valid?
  end

  test "admin? reflects the admin flag" do
    refute user.admin?
    assert user(admin: true).admin?
  end
end
