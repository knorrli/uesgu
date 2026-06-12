require 'db_test_helper'

# Scraper oversight under /admin/scrape_runs: gated to admins, and the index +
# show render a recorded sweep (status badges, per-scraper counts, the events it
# created) without view/i18n errors.
class AdminScrapeRunsTest < ActionDispatch::IntegrationTest
  test 'guests are sent to login, non-admins are forbidden' do
    get admin_scrape_runs_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get admin_scrape_runs_path
    assert_response :forbidden
  end

  test 'index renders before any run exists' do
    sign_in_as user(admin: true)

    get admin_scrape_runs_path
    assert_response :success
  end

  test 'index and show render a run, its results, and its created events' do
    run = ScrapeRun.create!(
      started_at: Time.zone.local(2030, 1, 1, 2, 0),
      finished_at: Time.zone.local(2030, 1, 1, 2, 5),
      status: :finished, scrapers_total: 2, scrapers_ok: 1, scrapers_empty: 1
    )
    run.scrape_results.create!(scraper: 'bad_bonn', status: :ok, rows_seen: 10,
                               created_count: 2, updated_count: 8, duration_ms: 1200)
    run.scrape_results.create!(scraper: 'docks', status: :empty, rows_seen: 0, duration_ms: 800)
    event(created_in_scrape_run: run, title: 'Linked Show')

    sign_in_as user(admin: true)

    get admin_scrape_runs_path
    assert_response :success
    assert_select '.scrape-badge--empty'

    get admin_scrape_run_path(run)
    assert_response :success
    assert_select 'body', text: /bad_bonn/
    assert_select 'body', text: /Linked Show/
  end

  test 'non-admins cannot trigger a run' do
    sign_in_as user(admin: false)
    assert_no_difference -> { ScrapeRun.count } do
      post admin_scrape_runs_path
    end
    assert_response :forbidden
  end

  test 'triggering creates a run and hands it off to the background sweep' do
    sign_in_as user(admin: true)
    handed_off = nil

    Scrapers::Sweep.stub(:enqueue, ->(run) { handed_off = run }) do
      assert_difference -> { ScrapeRun.count }, 1 do
        post admin_scrape_runs_path
      end
    end

    assert_redirected_to admin_scrape_runs_path
    assert handed_off.running?, 'the created run is handed to the sweep'
  end

  test 'a trigger is refused while a run is already in progress' do
    sign_in_as user(admin: true)
    ScrapeRun.create!(started_at: Time.current) # running + recent => in progress

    Scrapers::Sweep.stub(:enqueue, ->(_run) { flunk 'must not enqueue a second run' }) do
      assert_no_difference -> { ScrapeRun.count } do
        post admin_scrape_runs_path
      end
    end

    assert_redirected_to admin_scrape_runs_path
  end

  test 'the index shows a trigger button for admins' do
    sign_in_as user(admin: true)
    get admin_scrape_runs_path
    assert_select 'form[action=?][method=post]', admin_scrape_runs_path
  end

  test 'the admin dashboard links to scraper runs' do
    sign_in_as user(admin: true)

    get admin_path
    assert_response :success
    assert_select 'a[href=?]', admin_scrape_runs_path
  end
end
