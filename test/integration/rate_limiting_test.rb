require "db_test_helper"

# Rack::Attack is disabled in the test env by default (so other tests can hammer
# the app freely). These tests opt it in for the duration of each example and
# clear the counter store so runs don't bleed into each other.
class RateLimitingTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store.clear
  end

  teardown do
    Rack::Attack.enabled = false
    Rack::Attack.cache.store.clear
  end

  # A public IP — the localhost safelist exempts 127.0.0.1, which is where
  # integration requests originate by default.
  CLIENT = { "REMOTE_ADDR" => "203.0.113.7" }.freeze

  test "throttles a single IP past the per-minute limit" do
    limit = 60

    limit.times do
      get root_path, headers: CLIENT
      assert_response :success
    end

    get root_path, headers: CLIENT
    assert_response :too_many_requests
    assert_equal "60", response.headers["Retry-After"]
  end

  test "does not count fingerprinted asset requests toward the limit" do
    # Well past the limit, but asset paths are skipped — none should be throttled.
    70.times do
      get "/assets/whatever-deadbeef.css", headers: CLIENT
      assert_not_equal 429, response.status, "asset requests must never be throttled"
    end
  end

  test "never throttles the healthcheck endpoint" do
    70.times { get "/up", headers: CLIENT }
    assert_response :success
  end
end
