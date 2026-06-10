require 'db_test_helper'

# Locks TagsHelper's pure logic: the context→icon mapping, the canton fallback,
# and the hierarchical ordering of location tags (canton › city › venue, with
# unknown names appended). Derived from the live scraper hierarchy, not hardcoded.
class TagsHelperTest < ActionView::TestCase
  test 'tag_icon_class maps known contexts and falls back for the rest' do
    assert_equal 'ti-search', tag_icon_class(context: 'query')
    assert_equal 'ti-calendar', tag_icon_class(context: 'date')
    assert_equal 'ti-music-alt', tag_icon_class(context: 'styles')
    assert_equal 'ti-tag', tag_icon_class(context: 'genres')
    assert_equal 'ti-home', tag_icon_class(context: 'venue')
    assert_equal 'ti-location-pin', tag_icon_class(context: 'city')
    assert_equal 'ti-map-alt', tag_icon_class(context: 'canton')
    assert_equal 'ti-bolt', tag_icon_class(context: 'something-unknown')
  end

  test 'canton_name falls back to the raw code for an unknown canton' do
    assert_equal 'ZZ', canton_name('ZZ')
  end

  test 'hierarchical_location_names lists cantons alphabetically with venues present' do
    cantons = Location.hierarchy.keys
    skip 'no scrapers registered' if cantons.empty?

    names = hierarchical_location_names
    positions = cantons.sort.map { |c| names.index(c) }

    assert_equal positions, positions.sort, 'canton headers appear in alphabetical order'
    assert (Location.venue_names.to_a & names).any?, 'venues are included in the ordering'
  end

  test 'ordered_location_tags sorts hierarchy venues ahead of unknown locations' do
    venue = Location.venue_names.first
    skip 'no scrapers registered' if venue.nil?
    event(location_list: [venue, 'Zzz Unknown Place'])

    ordered = ordered_location_tags.map(&:name)

    assert_includes ordered, venue
    assert_includes ordered, 'Zzz Unknown Place'
    assert_operator ordered.index(venue), :<, ordered.index('Zzz Unknown Place')
  end

  test 'ordered_location_tags excludes already-applied names' do
    venue = Location.venue_names.first
    skip 'no scrapers registered' if venue.nil?
    event(location_list: [venue])

    refute_includes ordered_location_tags(applied: [venue]).map(&:name), venue
  end
end
