require 'db_test_helper'

# Read-only styles browser under /admin/styles: admin-gated, filterable by
# mapping status (a genre points at it, or it's an orphan), searchable.
class AdminStylesTest < ActionDispatch::IntegrationTest
  test 'guests are sent to login, non-admins are forbidden' do
    get admin_styles_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get admin_styles_path
    assert_response :forbidden
  end

  test 'an admin can browse styles filtered by mapping status' do
    mapped = style(name: 'mappedstyle')
    genre(styles: [mapped])
    orphan = style(name: 'orphanstyle')
    tagged = event
    tagged.style_list = [mapped.name]
    tagged.save!
    sign_in_as user(admin: true)

    get admin_styles_path
    assert_response :success
    assert_select 'a', text: mapped.name
    assert_select 'a', text: orphan.name

    get admin_styles_path(status: 'assigned')
    assert_select 'a', text: mapped.name
    assert_select 'a', text: orphan.name, count: 0

    get admin_styles_path(status: 'unassigned')
    assert_select 'a', text: orphan.name
    assert_select 'a', text: mapped.name, count: 0

    get admin_styles_path(q: 'orphan')
    assert_select 'a', text: orphan.name
    assert_select 'a', text: mapped.name, count: 0
  end
end
