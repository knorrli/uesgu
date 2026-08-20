require "db_test_helper"

# The capture funnel's oversight page under /admin/extraction_attempts: admin-gated,
# read-only. Asserts that the two signals the table exists for — provider failures
# and the codes for values the Normalizer refused — actually reach the page.
class AdminExtractionAttemptsTest < ActionDispatch::IntegrationTest
  test "guests are sent to login, non-admins are forbidden" do
    get admin_extraction_attempts_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get admin_extraction_attempts_path
    assert_response :forbidden
  end

  test "an admin sees the empty state before anything has been extracted" do
    sign_in_as user(admin: true)

    get admin_extraction_attempts_path

    assert_response :success
    assert_select "p.muted", text: I18n.t("admin.extraction_attempts.index.empty")
  end

  test "an admin sees the failure codes, the refused values and the prompt they came from" do
    ExtractionAttempt.create!(status: :ok, medium: "image", model: "gemma-test", prompt_sha: "abc123abc123",
                              candidates_count: 2, issues: { "time_unparseable" => 2, "canton_invalid" => 1 })
    ExtractionAttempt.create!(status: :failed, code: "provider_error", medium: "text",
                              model: "gemma-test", prompt_sha: "abc123abc123", error_message: "HTTP 503")
    sign_in_as user(admin: true)

    get admin_extraction_attempts_path

    assert_response :success
    assert_select "dt", text: "provider_error"
    assert_select "dt", text: "time_unparseable"
    assert_select "dd", text: "2"
    assert_select "td", text: "abc123abc123", minimum: 1
    assert_select "td", text: /HTTP 503/
  end
end
