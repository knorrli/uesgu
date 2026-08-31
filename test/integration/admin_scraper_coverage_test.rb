require "db_test_helper"

class AdminScraperCoverageTest < ActionDispatch::IntegrationTest
  test "guests are sent to login, non-admins are forbidden" do
    get admin_scraper_coverage_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get admin_scraper_coverage_path
    assert_response :forbidden
  end

  test "index renders with no events" do
    sign_in_as user(admin: true)

    get admin_scraper_coverage_path
    assert_response :success
  end

  test "index renders a per-scraper fill-rate row computed from events" do
    full = event(data_source: "Acme", start_time: Time.zone.local(2030, 1, 1, 20, 0),
                 description: "With support")
    full.update!(genre_list: ["zorptronic"])
    2.times { event(data_source: "Acme") }

    sign_in_as user(admin: true)
    get admin_scraper_coverage_path

    assert_response :success
    assert_select "td", text: "acme"
    assert_select ".coverage--low", text: "33%"
  end

  test "a declared field gap renders n/a (muted), not a red zero" do
    2.times do
      event(data_source: Scrapers::BadBonn.source_key,
            start_time: Time.zone.local(2030, 1, 1, 20, 0), description: "With support")
    end

    sign_in_as user(admin: true)
    get admin_scraper_coverage_path

    assert_response :success
    assert_select ".coverage--gap", text: "n/a"
    assert_select ".coverage--gap[title]"
    assert_select ".coverage--low", false
  end

  test "reality wins — a gapped field with real data shows the live percentage" do
    e = event(data_source: Scrapers::BadBonn.source_key,
              start_time: Time.zone.local(2030, 1, 1, 20, 0))
    e.update!(genre_list: ["zorptronic"])

    sign_in_as user(admin: true)
    get admin_scraper_coverage_path

    assert_response :success
    assert_select ".coverage--gap", false
    assert_select ".coverage", text: "100%"
  end
end
