require "db_test_helper"

class PageTitlesTest < ActionDispatch::IntegrationTest
  test "the home/listing page tab is just the brand (sets no title), never doubled" do
    get events_path
    assert_select "title", text: "üsgu"
    assert_no_match(/üsgu \| üsgu/, response.body, "the brand is never doubled")
  end

  test "a page that sets a title gets the brand prefixed exactly once" do
    get new_session_path
    assert_select "title", /\Aüsgu \| .+\z/
    assert_no_match(/üsgu \| üsgu/, response.body)
  end
end
