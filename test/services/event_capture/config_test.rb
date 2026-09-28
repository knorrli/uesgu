require "test_helper"

class EventCaptureConfigTest < ActiveSupport::TestCase
  def with_env(**pairs)
    original = pairs.keys.to_h { |key| [key, ENV[key]] }
    pairs.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| ENV[key] = value }
  end

  test "surrounding whitespace is trimmed off a pasted credential" do
    with_env("INFOMANIAK_API_TOKEN" => " tok-123\n", "INFOMANIAK_PRODUCT_ID" => "4242 ") do
      assert_equal "tok-123", EventCaptureConfig.api_token
      assert_equal "4242", EventCaptureConfig.product_id
      assert_predicate EventCaptureConfig, :configured?
    end
  end

  test "a blank env var falls through to credentials rather than blanking the config" do
    Rails.application.credentials.stub(:dig, "tok-from-credentials") do
      with_env("INFOMANIAK_API_TOKEN" => "   ") do
        assert_equal "tok-from-credentials", EventCaptureConfig.api_token
      end
    end
  end
end
