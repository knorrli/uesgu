require "db_test_helper"

# Scraper oversight under /admin/scrape_runs: gated to admins, and the index +
# show render a recorded sweep (status badges, per-scraper counts, the events it
# created) without view/i18n errors.
class AdminScrapeRunsTest < ActionDispatch::IntegrationTest
  test "guests are sent to login, non-admins are forbidden" do
    get admin_scrape_runs_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get admin_scrape_runs_path
    assert_response :forbidden
  end

  test "index renders before any run exists" do
    sign_in_as user(admin: true)

    get admin_scrape_runs_path
    assert_response :success
  end

  test "index and show render a run, its results, and its created events" do
    run = ScrapeRun.create!(
      started_at: Time.zone.local(2030, 1, 1, 2, 0),
      finished_at: Time.zone.local(2030, 1, 1, 2, 5),
      status: :finished, scrapers_total: 2, scrapers_ok: 1, scrapers_empty: 1
    )
    run.scrape_results.create!(scraper: "bad_bonn", status: :ok, rows_seen: 10,
                               created_count: 2, updated_count: 8, duration_ms: 1200)
    run.scrape_results.create!(scraper: "docks", status: :empty, rows_seen: 0, duration_ms: 800)
    event(created_in_scrape_run: run, title: "Linked Show")

    sign_in_as user(admin: true)

    get admin_scrape_runs_path
    assert_response :success
    assert_select ".scrape-badge--empty"

    get admin_scrape_run_path(run)
    assert_response :success
    assert_select "body", text: /bad_bonn/
    assert_select "body", text: /Linked Show/
    assert_select "input[name=scraper][value=?]", "bad_bonn" # a per-scraper re-run button
  end

  test "non-admins cannot trigger a run" do
    sign_in_as user(admin: false)
    assert_no_difference -> { ScrapeRun.count } do
      post admin_scrape_runs_path
    end
    assert_response :forbidden
  end

  test "triggering creates a run and hands the full registry to the sweep" do
    sign_in_as user(admin: true)
    handed_off = nil
    handed_scrapers = nil

    Scrapers::Sweep.stub(:enqueue, ->(run, scrapers:) { handed_off = run; handed_scrapers = scrapers }) do
      assert_difference -> { ScrapeRun.count }, 1 do
        post admin_scrape_runs_path
      end
    end

    assert_redirected_to admin_scrape_runs_path
    assert handed_off.running?, "the created run is handed to the sweep"
    assert_equal Scrapers::All.scrapers.size, handed_scrapers.size, "the whole registry runs"
  end

  test "triggering a single scraper limits the sweep to just that one" do
    sign_in_as user(admin: true)
    handed_scrapers = nil

    Scrapers::Sweep.stub(:enqueue, ->(_run, scrapers:) { handed_scrapers = scrapers }) do
      assert_difference -> { ScrapeRun.count }, 1 do
        post admin_scrape_runs_path, params: { scraper: "bad_bonn" }
      end
    end

    assert_equal ["bad_bonn"], handed_scrapers.keys.map(&:underscore)
  end

  test "an unknown scraper slug is refused without starting a run" do
    sign_in_as user(admin: true)

    Scrapers::Sweep.stub(:enqueue, ->(_run, scrapers:) { flunk "must not enqueue" }) do
      assert_no_difference -> { ScrapeRun.count } do
        post admin_scrape_runs_path, params: { scraper: "no_such_venue" }
      end
    end

    assert_redirected_to admin_scrape_runs_path
  end

  test "a trigger is refused while a run is already in progress" do
    sign_in_as user(admin: true)
    ScrapeRun.create!(started_at: Time.current) # running + recent => in progress

    Scrapers::Sweep.stub(:enqueue, ->(_run, scrapers:) { flunk "must not enqueue a second run" }) do
      assert_no_difference -> { ScrapeRun.count } do
        post admin_scrape_runs_path
      end
    end

    assert_redirected_to admin_scrape_runs_path
  end

  test "the index shows a trigger button for admins" do
    sign_in_as user(admin: true)
    get admin_scrape_runs_path
    assert_select "form[action=?][method=post]", admin_scrape_runs_path
  end

  test "snoozing a scraper mutes it, and waking clears the snooze" do
    sign_in_as user(admin: true)

    assert_difference -> { ScraperSnooze.active.count }, 1 do
      post snooze_admin_scrape_runs_path, params: { scraper: "bad_bonn" }
    end
    assert_redirected_to admin_scrape_runs_path
    assert ScraperSnooze.active_by_slug.key?("bad_bonn")

    assert_difference -> { ScraperSnooze.count }, -1 do
      post wake_admin_scrape_runs_path, params: { scraper: "bad_bonn" }
    end
    assert_redirected_to admin_scrape_runs_path
  end

  test "snooze refuses an unknown scraper slug" do
    sign_in_as user(admin: true)
    assert_no_difference -> { ScraperSnooze.count } do
      post snooze_admin_scrape_runs_path, params: { scraper: "no_such_venue" }
    end
    assert_redirected_to admin_scrape_runs_path
  end

  test "non-admins cannot snooze a scraper" do
    sign_in_as user(admin: false)
    assert_no_difference -> { ScraperSnooze.count } do
      post snooze_admin_scrape_runs_path, params: { scraper: "bad_bonn" }
    end
    assert_response :forbidden
  end

  test "a snoozed scraper shows a Wake button and its snoozed status on the index" do
    run = ScrapeRun.create!(started_at: Time.current, finished_at: Time.current, status: :finished)
    run.scrape_results.create!(scraper: "bad_bonn", status: :snoozed)
    ScraperSnooze.snooze!("bad_bonn")
    sign_in_as user(admin: true)

    get admin_scrape_runs_path
    assert_response :success
    assert_select "form[action=?]", wake_admin_scrape_runs_path
    assert_select ".scrape-badge--snoozed"
  end

  test "the admin dashboard links to scraper runs" do
    sign_in_as user(admin: true)

    get admin_path
    assert_response :success
    assert_select "a[href=?]", admin_scrape_runs_path
  end
end
