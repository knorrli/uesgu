require 'db_test_helper'

# Locks the location type derivation. Locations have no stored type — venue vs
# region is derived from the registered scrapers (each declares
# [venue, *aliases, city, canton]). Expectations are derived from the live
# Scrapers::All registry, never hardcoded venue names, so this stays correct as
# the fleet changes.
class LocationTest < ActiveSupport::TestCase
  setup do
    @scraper = Scrapers::All.scrapers.values.first
    skip 'no scrapers registered' if @scraper.nil?
  end

  test 'venue_names is the set of every scrapers declared venue' do
    assert_kind_of Set, Location.venue_names
    assert_includes Location.venue_names, @scraper.location
  end

  test 'a declared venue is classified as :venue' do
    assert Location.venue?(@scraper.location)
    assert_equal :venue, Location.type_for(@scraper.location)
  end

  test 'an unknown place is classified as a region (:city), not a venue' do
    refute Location.venue?('Definitely Not A Venue 9000')
    assert_equal :city, Location.type_for('Definitely Not A Venue 9000')
  end

  test 'a declared canton code is classified as :canton' do
    canton = @scraper.locations.last
    assert_equal :canton, Location.type_for(canton)
  end

  test 'a declared city is classified as :city' do
    city = @scraper.locations[-2]
    assert_equal :city, Location.type_for(city)
  end

  test 'hierarchy groups each venue under its canton and city' do
    locations = @scraper.locations
    canton = locations.last
    city = locations[-2]

    tree = Location.hierarchy

    assert_includes tree.keys, canton
    assert_includes tree[canton].keys, city
    assert_includes tree[canton][city], @scraper.location
  end
end
