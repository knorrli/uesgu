require "db_test_helper"

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

  test "the field leaderboard tells the three shapes apart" do
    attempt = ExtractionAttempt.create!(status: :ok, medium: "image", candidates_count: 1)
    ExtractionFieldOutcome.record!(
      attempt: attempt, candidate_index: 0,
      proposed: { "title" => "Zorpcore", "locality" => "Us", "time" => nil, "place" => "Zorpsaal" },
      accepted: { "title" => "Zorpcore", "locality" => "Zorpwil", "time" => "20:00", "place" => nil }
    )
    sign_in_as user(admin: true)

    get admin_extraction_attempts_path

    assert_response :success
    assert_select "h2", text: I18n.t("admin.extraction_attempts.index.fields_heading")
    assert_select "td", text: I18n.t("capture.candidate.locality")
    assert_select "table.scrape-table td", text: /100%/, minimum: 1
  end

  test "a prompt sha narrows the page to that prompt" do
    ExtractionAttempt.create!(status: :ok, medium: "image", model: "gemma-test", prompt_sha: "aaaaaaaaaaaa",
                              issues: { "time_unparseable" => 1 })
    ExtractionAttempt.create!(status: :ok, medium: "text", model: "gemma-test", prompt_sha: "bbbbbbbbbbbb",
                              issues: { "canton_invalid" => 1 })
    sign_in_as user(admin: true)

    get admin_extraction_attempts_path(prompt_sha: "aaaaaaaaaaaa")

    assert_response :success
    assert_select "dt", text: "time_unparseable"
    assert_select "dt", text: "canton_invalid", count: 0
    assert_select "a[href=?]", admin_extraction_attempts_path, text: I18n.t("admin.extraction_attempts.index.clear_filter")
  end
end
