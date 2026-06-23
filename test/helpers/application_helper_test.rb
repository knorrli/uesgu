require "db_test_helper"

# Locks ApplicationHelper#external_url: the href guard that keeps scraped/source
# URLs from smuggling a non-http scheme (javascript:/data:) into an admin click.
class ApplicationHelperTest < ActionView::TestCase
  test "external_url passes through http and https URLs unchanged" do
    assert_equal "https://example.com/path?q=1", external_url("https://example.com/path?q=1")
    assert_equal "http://example.com", external_url("HTTP://example.com".downcase)
  end

  test "external_url neutralizes non-http schemes and blanks" do
    assert_equal "#", external_url("javascript:alert(1)")
    assert_equal "#", external_url("data:text/html,<script>")
    assert_equal "#", external_url("/relative/path")
    assert_equal "#", external_url(nil)
    assert_equal "#", external_url("")
  end
end
