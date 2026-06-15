require "test_helper"

class InstallPageTest < ActionDispatch::IntegrationTest
  test "public install page renders for guests with the install block" do
    get install_path
    assert_response :success
    assert_select "[data-controller='install']"
    assert_select "[data-install-target='button']"
    assert_select "[data-install-target='firefox']"
  end
end
