require 'db_test_helper'

# Locks the favorites endpoints: the inline heart toggle (add/remove a single
# location or style) and the bulk update, plus their auth + validation guards.
class FavoritesTest < ActionDispatch::IntegrationTest
  test 'toggle adds then removes a location favorite' do
    u = sign_in_as user

    post toggle_favorites_path, params: { type: 'location', value: 'Invented Venue' }
    assert_response :no_content
    assert_includes u.reload.location_list, 'Invented Venue'

    post toggle_favorites_path, params: { type: 'location', value: 'Invented Venue' }
    assert_response :no_content
    refute_includes u.reload.location_list, 'Invented Venue'
  end

  test 'toggle follows a style onto the style list' do
    u = sign_in_as user
    post toggle_favorites_path, params: { type: 'style', value: 'wubstep' }
    assert_includes u.reload.style_list, 'wubstep'
  end

  test 'toggle rejects an unknown type or blank value' do
    sign_in_as user
    post toggle_favorites_path, params: { type: 'genre', value: 'x' }
    assert_response :unprocessable_entity
    post toggle_favorites_path, params: { type: 'location', value: '  ' }
    assert_response :unprocessable_entity
  end

  test 'bulk update replaces the favorite lists' do
    u = sign_in_as user
    patch favorites_path, params: { user: { location_list: ['Venue A'], style_list: ['glimmercore'] } }
    assert_redirected_to favorites_path
    assert_equal ['Venue A'], u.reload.location_list
    assert_equal ['glimmercore'], u.style_list
  end

  test 'toggling requires authentication' do
    post toggle_favorites_path, params: { type: 'location', value: 'X' }
    assert_redirected_to new_session_path
  end
end
