require "db_test_helper"
require "capybara/cuprite"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  BOOT_TIMEOUT = ENV["CI"] ? 60 : 20

  driven_by :cuprite,
    screen_size: [1300, 900],
    options: {
      headless: ENV["HEADLESS"] != "0",
      process_timeout: BOOT_TIMEOUT,
      timeout: 15,
      browser_path: ENV["CHROME_PATH"].presence
    }.compact

  NO_MOTION_CSS = "*,*::before,*::after{transition:none!important;animation:none!important}"

  def visit(*)
    super
    execute_script(
      "var s=document.createElement('style');s.textContent=#{NO_MOTION_CSS.inspect};" \
      "document.head.appendChild(s)"
    )
  end

  def sign_in_as(user, password: TaxonomyFixtures::PASSWORD)
    visit new_session_path
    fill_in "username", with: user.username
    fill_in "password", with: password
    find("input[type=submit]").click
    user
  end
end
