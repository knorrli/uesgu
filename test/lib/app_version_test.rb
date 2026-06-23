require "test_helper"

# AppVersion turns whatever git/REVISION reports into a display string and the
# best matching GitHub URL. `current` is memoised + environment-dependent, so we
# stub it and assert the classification (url + release_tag?) around it.
class AppVersionTest < ActiveSupport::TestCase
  test "a clean version tag links to its GitHub release" do
    AppVersion.stub(:current, "v0.1.0") do
      assert AppVersion.release_tag?
      assert_equal "https://github.com/knorrli/uesgu/releases/tag/v0.1.0", AppVersion.url
    end
  end

  test "a bare commit SHA links to the commit" do
    AppVersion.stub(:current, "a1b2c3d") do
      refute AppVersion.release_tag?
      assert_equal "https://github.com/knorrli/uesgu/commit/a1b2c3d", AppVersion.url
    end
  end

  test "a between-tags describe string falls back to the commit history" do
    AppVersion.stub(:current, "v0.1.0-3-ga1b2c3d") do
      refute AppVersion.release_tag?
      assert_equal "https://github.com/knorrli/uesgu/commits", AppVersion.url
    end
  end
end
