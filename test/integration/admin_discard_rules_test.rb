require "db_test_helper"

# Admin CRUD over discard rules, plus the live preview. Every write re-derives
# the discard flag across existing events so a rule takes effect immediately.
class AdminDiscardRulesTest < ActionDispatch::IntegrationTest
  test "guests are sent to login, non-admins are forbidden" do
    get admin_discard_rules_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get admin_discard_rules_path
    assert_response :forbidden
  end

  test "the index, new and edit pages render" do
    rule = DiscardRule.create!(pattern: "zorp", note: "football")
    sign_in_as user(admin: true)

    get admin_discard_rules_path
    assert_response :success
    assert_select "code", text: "zorp"

    get new_admin_discard_rule_path
    assert_response :success
    assert_select "input[name=?]", "discard_rule[pattern]"
    assert_select "turbo-frame#discard_rule_preview"

    get edit_admin_discard_rule_path(rule)
    assert_response :success
    assert_select "input[name=?][value=?]", "discard_rule[pattern]", "zorp"
  end

  test "creating a rule discards matching existing events right away" do
    junk = event(title: "zorp fest")
    keep = event(title: "real concert")
    sign_in_as user(admin: true)

    assert_difference -> { DiscardRule.count }, 1 do
      post admin_discard_rules_path, params: { discard_rule: { pattern: "zorp", active: "1" } }
    end
    assert_redirected_to admin_discard_rules_path

    assert junk.reload.discarded?
    refute keep.reload.discarded?
  end

  test "rejects an invalid (too-short) pattern" do
    sign_in_as user(admin: true)
    assert_no_difference -> { DiscardRule.count } do
      post admin_discard_rules_path, params: { discard_rule: { pattern: "z", active: "1" } }
    end
    assert_response :unprocessable_entity
  end

  test "deactivating a rule releases the events it filtered" do
    junk = event(title: "zorp fest")
    rule = DiscardRule.create!(pattern: "zorp")
    DiscardRule.reapply_all!
    assert junk.reload.discarded?
    sign_in_as user(admin: true)

    patch admin_discard_rule_path(rule), params: { discard_rule: { pattern: "zorp", active: "0" } }
    assert_redirected_to admin_discard_rules_path
    refute junk.reload.discarded?
  end

  test "deleting a rule brings its events back" do
    junk = event(title: "zorp fest")
    rule = DiscardRule.create!(pattern: "zorp")
    DiscardRule.reapply_all!
    sign_in_as user(admin: true)

    delete admin_discard_rule_path(rule)
    assert_redirected_to admin_discard_rules_path
    refute junk.reload.discarded?
  end

  test "preview lists the events a pattern would catch without saving" do
    event(title: "zorp fest")
    sign_in_as user(admin: true)

    assert_no_difference -> { DiscardRule.count } do
      get preview_admin_discard_rules_path(pattern: "zorp")
    end
    assert_response :success
    assert_select "turbo-frame#discard_rule_preview", text: /zorp fest/
  end
end
