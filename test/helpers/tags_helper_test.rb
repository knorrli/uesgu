require "db_test_helper"

# Locks TagsHelper's pure logic: the context→icon mapping, the canton fallback,
# and the hierarchical ordering of location tags (canton › city › venue, with
# unknown names appended). Derived from the live scraper hierarchy, not hardcoded.
class TagsHelperTest < ActionView::TestCase
  test "tag_icon_glyph maps known contexts and falls back for the rest" do
    assert_equal "ph-magnifying-glass", tag_icon_glyph(context: "query")
    assert_equal "ph-calendar-dots", tag_icon_glyph(context: "date")
    assert_equal "ph-tag", tag_icon_glyph(context: "genres")
    assert_equal "ph-house", tag_icon_glyph(context: "venue")
    assert_equal "ph-map-pin", tag_icon_glyph(context: "city")
    assert_equal "ph-map-trifold", tag_icon_glyph(context: "canton")
    assert_equal "ph-lightning", tag_icon_glyph(context: "something-unknown")
  end

  test "tag_icon_class prefixes the glyph with the Phosphor base weight" do
    assert_equal "ph ph-house", tag_icon_class(context: "venue")
    assert_equal "ph ph-map-pin", tag_icon_class(context: "city")
  end

  test "canton_name falls back to the raw code for an unknown canton" do
    assert_equal "ZZ", canton_name("ZZ")
  end

  # The locations filter dropdown is now a flat alphabetical list (matching the
  # styles dropdown) via available_tags(context: :locations); the former
  # hierarchical ordering helpers were removed with the flatten.
  test "available_tags(:locations) lists location tags alphabetically, excluding applied" do
    venue = Location.venue_names.first
    skip "no scrapers registered" if venue.nil?
    event(location_list: [venue, "Zzz Unknown Place"])

    names = available_tags(context: :locations).map(&:name)
    assert_equal names, names.sort, "alphabetical"
    assert_includes names, venue
    assert_includes names, "Zzz Unknown Place"

    refute_includes available_tags(context: :locations, applied: [venue]).map(&:name), venue
  end

  test "genre_filter_tree nests roots, sums subtree counts, prunes empties and unplaced" do
    rock = genre(name: "treerock", events_count: 1)
    indie = genre(name: "treeindie", events_count: 2); indie.set_parent!(rock)
    shoegaze = genre(name: "treeshoe", events_count: 3); shoegaze.set_parent!(indie)
    empty = genre(name: "treeempty", events_count: 0); empty.set_parent!(rock)
    loose = genre(name: "treeloose", events_count: 5) # top-level but childless = unplaced

    tree = genre_filter_tree
    root = tree.find { |node| node[:name] == rock.name }

    assert root, "a root genre (top-level with children) is present"
    assert_equal 6, root[:count], "subtree count sums self + every descendant (1+2+3)"
    indie_node = root[:children].find { |node| node[:name] == indie.name }
    assert_equal [shoegaze.name], indie_node[:children].map { |node| node[:name] }
    refute root[:children].any? { |node| node[:name] == empty.name }, "a zero-count subtree is pruned"
    refute tree.any? { |node| node[:value] == loose.name }, "an unplaced childless top-level genre is excluded"
  end
end
