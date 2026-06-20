require 'db_test_helper'

# Scraper data-coverage matrix under /admin/scraper_coverage: admin-gated, and the
# index renders per-scraper fill-rates (time / subtitle / genre) computed live
# from each scraper's events — without view/i18n errors.
class AdminScraperCoverageTest < ActionDispatch::IntegrationTest
  test 'guests are sent to login, non-admins are forbidden' do
    get admin_scraper_coverage_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get admin_scraper_coverage_path
    assert_response :forbidden
  end

  test 'index renders with no events' do
    sign_in_as user(admin: true)

    get admin_scraper_coverage_path
    assert_response :success
  end

  test 'index renders a per-scraper fill-rate row computed from events' do
    # Source "Acme": 3 events, one fully populated (time + subtitle + genre), two
    # bare → 33% on every facet, which trips the low-coverage flag (< 50%).
    full = event(data_source: 'Acme', start_time: Time.zone.local(2030, 1, 1, 20, 0),
                 subtitle: 'With support')
    full.update!(genre_list: ['zorptronic'])
    2.times { event(data_source: 'Acme') }

    sign_in_as user(admin: true)
    get admin_scraper_coverage_path

    assert_response :success
    assert_select 'td', text: 'acme'
    assert_select '.coverage--low', text: '33%'
  end
end
