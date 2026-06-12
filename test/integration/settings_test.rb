require 'db_test_helper'

# Locks the settings update: persists preferences, and treats a blank password
# as "leave unchanged" rather than clearing it.
class SettingsTest < ActionDispatch::IntegrationTest
  test 'update persists notification frequency and locale' do
    u = sign_in_as user(notification_frequency: 'never')
    patch settings_path, params: { user: { notification_frequency: 'weekly', locale: 'en' } }
    assert_redirected_to settings_path

    u.reload
    assert_equal 'weekly', u.notification_frequency
    assert_equal 'en', u.locale
  end

  test 'a blank password leaves the existing password intact' do
    u = sign_in_as user
    patch settings_path, params: { user: { notification_frequency: 'daily', password: '' } }
    assert_redirected_to settings_path

    assert u.reload.authenticate(PASSWORD), 'old password still works'
  end

  test 'settings require authentication' do
    get settings_path
    assert_redirected_to new_session_path
  end

  test 'settings page renders the account, notifications and delete sections' do
    sign_in_as user
    get settings_path

    assert_response :success
    assert_select 'section.settings-section', 3
    # One save button per editable section (account + notifications).
    assert_select 'input[type=submit]', 2
    # The per-device "on this device" cluster (install / push).
    assert_select '.settings-subsection'
  end
end
