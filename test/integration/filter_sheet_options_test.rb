require "db_test_helper"

# The filter sheets' option trees are NOT part of the page: the What genre
# tree and the Where place tree are ~360 checkbox rows between them, about half the
# feed's compressed weight, rendered on every request for a picker most visits never
# open. The page ships a turbo-frame instead, and filter-sheets#open fetches the rows
# on first open.
#
# Two things have to hold for that to be safe, and both are locked here:
#   1. nothing fetches the tree on its own — the URL rides in data-src, not src, so
#      neither Turbo's lazy loading nor a crawler walks into a fresh faceted URL space;
#   2. the applied values are still in the form before the tree lands, staged inside
#      the frame — otherwise removing one chip would drop every other applied filter,
#      and Save in the rule editor would wipe the rule's genres.
class FilterSheetOptionsTest < ActionDispatch::IntegrationTest
  test "the feed ships the sheet frames but none of their option rows" do
    genre_in_tree("Zylofeed")
    event(start_date: Date.current + 3, location_list: ["BE"])

    get events_path

    assert_response :success
    %w[what where].each do |field|
      assert_select "turbo-frame##{"filter_sheet_#{field}"}[data-src]"
      # No src: the frame must sit inert until a real user opens the sheet.
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
    # The frame carries them to the tree too, so it comes back with the same ticks.
    assert_select "turbo-frame#filter_sheet_what[data-src*='g%5B%5D=#{leaf.name}']"
  end

  test "the what endpoint returns the genre tree, pre-checked, in the sheet's frame" do
    leaf = genre_in_tree("Zylopicked")
    other = genre_in_tree("Zyloother")

    get filter_options_tags_path(field: "what", g: [leaf.name])

    assert_response :success
    # The frame id must match the one on the page — a miss would blank the frame and
    # take the staged values with it.
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
    get "/tags/filter_options/when" # a real sheet, but its options aren't lazy
    assert_response :not_found
    # The constraint matches the WHOLE segment, so no partial match slips through to
    # the controller's partial lookup.
    get "/tags/filter_options/whatever"
    assert_response :not_found
  end

  private

  # A genre that actually renders in the tree: a root (no events) with one in-use
  # child, so genre_filter_tree keeps the subtree. Returns the child (the leaf you
  # filter by).
  def genre_in_tree(name)
    root = genre(name: "#{name}root", events_count: 0)
    leaf = genre(name: name, events_count: 1)
    leaf.set_parent!(root)
    leaf
  end
end
