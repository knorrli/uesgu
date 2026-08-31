require "db_test_helper"

class TagsHelperTest < ActionView::TestCase
  test "tag_icon_glyph maps known contexts and falls back for the rest" do
    assert_equal "ph-magnifying-glass", tag_icon_glyph(context: "query")
    assert_equal "ph-calendar-dots", tag_icon_glyph(context: "date")
    assert_equal "ph-tag", tag_icon_glyph(context: "genres")
    assert_equal "ph-house", tag_icon_glyph(context: "venue")
    assert_equal "ph-map-pin", tag_icon_glyph(context: "locality")
    assert_equal "ph-map-trifold", tag_icon_glyph(context: "canton")
    assert_equal "ph-lightning", tag_icon_glyph(context: "something-unknown")
  end

  test "tag_icon_class prefixes the glyph with the Phosphor base weight" do
    assert_equal "ph ph-house", tag_icon_class(context: "venue")
    assert_equal "ph ph-map-pin", tag_icon_class(context: "locality")
  end

  test "location_filter_tree labels a canton by its code, keeping the name searchable" do
    spot = place(name: "Zorpsaal", locality: "Zorpwil", canton: "GE")
    event(location_list: [spot.name, spot.locality, spot.canton])

    node = location_filter_tree.find { |n| n[:value] == "GE" }

    assert_equal "GE", node[:name]
    assert_equal Location.canton_name("GE"), node[:title]
    assert_includes node[:search].split, "GE"
    assert_includes node[:search], Location.canton_name("GE")
  end

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
    loose = genre(name: "treeloose", events_count: 5)

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
