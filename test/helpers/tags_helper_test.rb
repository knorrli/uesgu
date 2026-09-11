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

  test "genre_filter_tree nests roots, counts distinct subtree events, prunes empties and unplaced" do
    rock = genre(name: "treerock")
    indie = genre(name: "treeindie"); indie.set_parent!(rock)
    shoegaze = genre(name: "treeshoe"); shoegaze.set_parent!(indie)
    empty = genre(name: "treeempty"); empty.set_parent!(rock)
    loose = genre(name: "treeloose"); event_with_genres(loose.name)
    event_with_genres(rock.name)
    event_with_genres(indie.name, shoegaze.name)
    event_with_genres(shoegaze.name)

    tree = genre_filter_tree
    root = tree.find { |node| node[:name] == rock.name }

    assert root, "a root genre (top-level with children) is present"
    assert_equal 3, root[:count], "an event tagged with both a genre and its child counts once"
    indie_node = root[:children].find { |node| node[:name] == indie.name }
    assert_equal 2, indie_node[:count]
    assert_equal [shoegaze.name], indie_node[:children].map { |node| node[:name] }
    refute root[:children].any? { |node| node[:name] == empty.name }, "a zero-count subtree is pruned"
    refute tree.any? { |node| node[:value] == loose.name }, "an unplaced childless top-level genre is excluded"
  end

  test "genre_filter_tree counts only the events the filter would list" do
    rock = genre(name: "countrock")
    punk = genre(name: "countpunk"); punk.set_parent!(rock)
    event_with_genres(punk.name)
    event(start_date: Date.current - 1.day).update!(genre_list: [punk.name])
    event(hidden: true).update!(genre_list: [punk.name])

    node = genre_filter_tree.find { |n| n[:value] == rock.name }

    assert_equal 1, node[:count], "a past or hidden event is not listed, so it is not counted"
  end

  test "genre_filter_tree counts events tagged with a merged-away alias under the canonical" do
    rock = genre(name: "aliasrock")
    punk = genre(name: "aliaspunk"); punk.set_parent!(rock)
    old_name = genre(name: "aliasoldpunk")
    event_with_genres(old_name.name)
    old_name.merge_into!(punk)

    node = genre_filter_tree.find { |n| n[:value] == rock.name }

    assert_equal 1, node[:count], "the filter expands to alias names, so the count has to follow"
  end

  test "location_filter_tree counts only the events the filter would list" do
    spot = place(name: "Countsaal", locality: "Countwil", canton: "GE")
    tags = [spot.name, spot.locality, spot.canton]
    event(location_list: tags)
    event(start_date: Date.current - 1.day, location_list: tags)
    event(hidden: true, location_list: tags)

    canton = location_filter_tree.find { |n| n[:value] == "GE" }
    locality = canton[:children].find { |n| n[:value] == spot.locality }
    venue = locality[:children].find { |n| n[:value] == spot.name }

    assert_equal [1, 1, 1], [canton[:count], locality[:count], venue[:count]]
  end

  test "location_filter_tree drops a venue whose only events have passed" do
    spot = place(name: "Pastsaal", locality: "Pastwil", canton: "GE")
    event(start_date: Date.current - 1.day, location_list: [spot.name, spot.locality, spot.canton])

    refute location_filter_tree.any? { |n| n[:value] == "GE" }
  end
end
