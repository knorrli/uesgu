require 'db_test_helper'

# Locks the settings update: persists preferences, and treats a blank password
# as "leave unchanged" rather than clearing it.
class SettingsTest < ActionDispatch::IntegrationTest
  test 'update persists the locale' do
    u = sign_in_as user
    patch settings_path, params: { user: { locale: 'en' } }
    assert_redirected_to settings_path

    assert_equal 'en', u.reload.locale
  end

  test 'a blank password leaves the existing password intact' do
    u = sign_in_as user
    patch settings_path, params: { user: { locale: 'de', password: '' } }
    assert_redirected_to settings_path

    assert u.reload.authenticate(PASSWORD), 'old password still works'
  end

  test 'settings require authentication' do
    get settings_path
    assert_redirected_to new_session_path
  end

  test 'settings page renders the account and delete sections, logout in the header' do
    sign_in_as user
    get settings_path

    assert_response :success
    # Account section + its single save form (language/email/password share one
    # form), and the delete-account section. The per-device notifications section
    # only renders when web push is configured, so it's absent here.
    assert_select 'h2', text: I18n.t('settings.account_heading')
    assert_select 'input[type=submit]', 1
    assert_select 'h2', text: I18n.t('settings.delete_account_heading')
    # Logout is a page-level action in the header (no longer its own section).
    assert_select 'form[action=?][method=post] button', session_path
    # Install moved to the top nav — it's not on the settings page anymore.
    assert_select '.install-block', false
  end
end
