require 'db_test_helper'

# Scraper data-coverage matrix under /admin/scraper_coverage: admin-gated, and the
# index renders per-scraper fill-rates (time / description / genre) computed live
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
    # Source "Acme": 3 events, one fully populated (time + description + genre), two
    # bare → 33% on every facet, which trips the low-coverage flag (< 50%).
    full = event(data_source: 'Acme', start_time: Time.zone.local(2030, 1, 1, 20, 0),
                 description: 'With support')
    full.update!(genre_list: ['zorptronic'])
    2.times { event(data_source: 'Acme') }

    sign_in_as user(admin: true)
    get admin_scraper_coverage_path

    assert_response :success
    assert_select 'td', text: 'acme'
    assert_select '.coverage--low', text: '33%'
  end

  # A scraper can declare (via Scrapers::Agent.field_gaps) that its source simply
  # doesn't expose a field — that's a settled absence, shown muted as "n/a", never
  # flagged red like a broken extractor. Bad Bonn declares genres: :no_field.
  test 'a declared field gap renders n/a (muted), not a red zero' do
    # Populate the fields Bad Bonn *does* provide (time + description) so genres is
    # the only empty facet — isolating the gap from ordinary low-coverage cells.
    2.times do
      event(data_source: Scrapers::BadBonn.source_key,
            start_time: Time.zone.local(2030, 1, 1, 20, 0), description: 'With support')
    end

    sign_in_as user(admin: true)
    get admin_scraper_coverage_path

    assert_response :success
    # The genre cell is the declared gap: "n/a", muted (--gap), with the reason on hover.
    assert_select '.coverage--gap', text: 'n/a'
    assert_select '.coverage--gap[title]'
    # ...and it must NOT be flagged as a low/broken extractor.
    assert_select '.coverage--low', false
  end

  # Honesty guard: a gap declaration only suppresses the red flag while the field
  # is genuinely empty. If the scraper ever does collect the field, the live
  # percentage wins over the stale declaration rather than masking real data.
  test 'reality wins — a gapped field with real data shows the live percentage' do
    e = event(data_source: Scrapers::BadBonn.source_key,
              start_time: Time.zone.local(2030, 1, 1, 20, 0))
    e.update!(genre_list: ['zorptronic'])

    sign_in_as user(admin: true)
    get admin_scraper_coverage_path

    assert_response :success
    # Genres now at 100% for this source → the declaration is ignored, no gap cell.
    assert_select '.coverage--gap', false
    assert_select '.coverage', text: '100%'
  end
end
