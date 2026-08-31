require "db_test_helper"

class FilterSheetOptionsTest < ActionDispatch::IntegrationTest
  test "the feed ships the sheet frames but none of their option rows" do
    genre_in_tree("Zylofeed")
    event(start_date: Date.current + 3, location_list: ["BE"])

    get events_path

    assert_response :success
    %w[what where].each do |field|
      assert_select "turbo-frame##{"filter_sheet_#{field}"}[data-src]"
      assert_select "turbo-frame##{"filter_sheet_#{field}"}[src]", false
      assert_select ".sheet[data-field=#{field}] .opt--top", false
    end
  end

  test "applied values are staged in the frame, so an unopened sheet still submits them" do
    leaf = genre_in_tree("Zylostaged")
    event(start_date: Date.current + 3, genre_list: [leaf.name], location_list: ["BE"])

    get events_path(g: [leaf.name], l: ["BE"])

    assert_response :success
    assert_select "turbo-frame#filter_sheet_what input[name='g[]'][value='#{leaf.name}'][checked]"
    assert_select "turbo-frame#filter_sheet_where input[name='l[]'][value='BE'][checked]"
    assert_select "turbo-frame#filter_sheet_what[data-src*='g%5B%5D=#{leaf.name}']"
  end

  test "the what endpoint returns the genre tree, pre-checked, in the sheet's frame" do
    leaf = genre_in_tree("Zylopicked")
    other = genre_in_tree("Zyloother")

    get filter_options_tags_path(field: "what", g: [leaf.name])

    assert_response :success
    assert_select "turbo-frame#filter_sheet_what" do
      assert_select "input[name='g[]'][value='#{leaf.name}'][checked]"
      assert_select "input[name='g[]'][value='#{other.name}']"
      assert_select "input[name='g[]'][value='#{other.name}'][checked]", false
    end
  end

  test "the where endpoint returns the place tree, pre-checked, in the sheet's frame" do
    event(start_date: Date.current + 3, location_list: ["BE"])

    get filter_options_tags_path(field: "where", l: ["BE"])

    assert_response :success
    assert_select "turbo-frame#filter_sheet_where input[name='l[]'][value='BE'][checked]"
  end

  test "the endpoint is public — the feed's filter works signed out" do
    genre_in_tree("Zyloanon")

    get filter_options_tags_path(field: "what")

    assert_response :success
  end

  test "only the two known fields are routable" do
    get "/tags/filter_options/when"
    assert_response :not_found
    get "/tags/filter_options/whatever"
    assert_response :not_found
  end

  private

  def genre_in_tree(name)
    root = genre(name: "#{name}root", events_count: 0)
    leaf = genre(name: name, events_count: 1)
    leaf.set_parent!(root)
    leaf
  end
end
