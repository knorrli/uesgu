# Browser-driven system tests. Cuprite talks CDP to the system Chrome via Ferrum
# — no chromedriver/Selenium binary, no downloaded browser. `bin/rails test:system`.
#
# We require db_test_helper (not the DB-free test_helper) so system tests get
# rails/test_help + the shared fixtures (TaxonomyFixtures: user/event/...).
require "db_test_helper"
require "capybara/cuprite"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # headless by default; set HEADLESS=0 to watch a run, CHROME_PATH to override
  # the auto-detected browser binary.
  driven_by :cuprite,
    screen_size: [1300, 900],
    options: {
      headless: ENV["HEADLESS"] != "0",
      process_timeout: 20,
      timeout: 15,
      browser_path: ENV["CHROME_PATH"].presence
    }.compact

  # Sign in through the real login form. (The integration `sign_in_as` posts to
  # the session controller and only sets the test's cookie jar — that doesn't
  # carry into the browser, so the browser must log in for real.)
  def sign_in_as(user, password: TaxonomyFixtures::PASSWORD)
    visit new_session_path
    fill_in "username", with: user.username
    fill_in "password", with: password
    find("input[type=submit]").click
    user
  end
end
