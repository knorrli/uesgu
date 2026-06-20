require 'db_test_helper'

# The living styleguide is an admin-only reference page. Lock the gate (guest ->
# login, non-admin -> 403, admin -> renders) and prove the view actually renders
# without an ERB/helper error, since it's hand-written markup that's easy to
# break silently.
class StyleguideTest < ActionDispatch::IntegrationTest
  test 'guests are sent to login' do
    get styleguide_path
    assert_redirected_to new_session_path
  end

  test 'authenticated non-admins are forbidden' do
    sign_in_as user(admin: false)
    get styleguide_path
    assert_response :forbidden
  end

  test 'admins get the rendered styleguide' do
    sign_in_as user(admin: true)
    get styleguide_path

    assert_response :success
    assert_select 'h1', text: /styleguide/i
    # A few representative specimens across the categories prove the real
    # element classes made it into the page.
    assert_select 'input[type=submit]'
    assert_select '.button-small.danger'
    assert_select '.icon-button.danger'
    assert_select '.scrape-badge--ok'
    assert_select '.funnel-fill'
  end
end
