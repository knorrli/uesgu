require "test_helper"

class FooterPagesTest < ActionDispatch::IntegrationTest
  test "about page renders for guests" do
    get about_path
    assert_response :success
    assert_select "h1", text: "Über üsgu"
    # Links onward to the privacy notice.
    assert_select "a[href=?]", privacy_path
  end

  test "privacy page renders for guests" do
    get privacy_path
    assert_response :success
    assert_select "h1", text: "Datenschutz"
    # Contact address is present as text (no mailto yet — inbound forwarding
    # is still an open blocker), so the page must not link it.
    assert_select "body", text: /kontakt@uesgu\.ch/
    assert_select "a[href^='mailto:']", count: 0
  end

  test "footer appears on every page with both links" do
    get root_path
    assert_response :success
    assert_select "footer.site-footer" do
      assert_select "a[href=?]", about_path
      assert_select "a[href=?]", privacy_path
    end
  end

  test "footer shows the deployed version, linked to GitHub" do
    get root_path
    assert_response :success
    assert_select "footer.site-footer a.site-footer__version", text: AppVersion.current do |links|
      assert_match %r{\Ahttps://github\.com/knorrli/uesgu/}, links.first["href"]
    end
  end
end
