require 'db_test_helper'

# Locks EventsHelper's predicate/URL logic (the fiddly bits that break silently):
# calendar nav URL surgery, follow-state lookups, and the "is the active filter
# exactly my favorites" comparison.
class EventsHelperTest < ActionView::TestCase
  # The helper resolves current_user via the controller; provide it for the test.
  attr_writer :current_user
  def current_user = @current_user

  test 'calendar_nav_path drops the open day but preserves the filter' do
    result = calendar_nav_path('http://test.host/events?view=calendar&day=2030-01-01&l%5B%5D=Venue')
    query = Rack::Utils.parse_nested_query(URI.parse(result).query)

    refute query.key?('day'), 'changing months collapses the open day'
    assert_equal 'calendar', query['view']
    assert_equal ['Venue'], query['l']
  end

  test 'calendar_nav_path clears the query entirely when only the day was set' do
    result = calendar_nav_path('http://test.host/events?day=2030-01-01')
    assert_nil URI.parse(result).query
  end

  test 'followed_tag? checks the matching favorite list' do
    self.current_user = user(location_list: ['VenueX'], style_list: ['styleY'])

    assert followed_tag?(:location, 'VenueX')
    refute followed_tag?(:location, 'Unfollowed')
    assert followed_tag?(:style, 'styleY')
    refute followed_tag?(:genre, 'anything'), 'genres are not followable'
  end

  test 'favorite_followed_keys namespaces locations and styles' do
    self.current_user = user(location_list: ['VenueX'], style_list: ['styleY'])
    keys = favorite_followed_keys

    assert_includes keys, 'l:VenueX'
    assert_includes keys, 's:styleY'
  end

  test 'favorites_filter_available? is false without a logged-in user' do
    self.current_user = nil
    refute favorites_filter_available?
  end

  test 'favorites_filter_available? is false when the user follows nothing' do
    self.current_user = user
    refute favorites_filter_available?
  end

  test 'favorites_filter_available? is true with at least one follow' do
    self.current_user = user(style_list: ['styleY'])
    assert favorites_filter_available?
  end

  test 'favorites_filter_active? matches the filter against follows, order-independent' do
    self.current_user = user(location_list: %w[A B], style_list: ['s'])
    @filter = Filter.new
    @filter.location_list = 'B, A' # same set, different order
    @filter.style_list = 's'

    assert favorites_filter_active?
  end

  test 'favorites_filter_active? is false when the filter differs from follows' do
    self.current_user = user(location_list: ['A'])
    @filter = Filter.new
    @filter.location_list = 'A'
    @filter.style_list = 'extra-not-followed'

    refute favorites_filter_active?
  end
end
