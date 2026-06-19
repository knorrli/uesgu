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

  test 'favorites_filter_active? is false when an extra free-text query is layered on' do
    self.current_user = user(location_list: %w[A B], style_list: ['s'])
    @filter = Filter.new
    @filter.location_list = 'A, B'
    @filter.style_list = 's'
    @filter.queries = 'extra' # exact follows PLUS a query is no longer "just my favorites"

    refute favorites_filter_active?
  end

  test 'genre_subtree_names returns the genre plus every descendant' do
    rock = genre(name: 'helprock')
    indie = genre(name: 'helpindie'); indie.set_parent!(rock)
    shoegaze = genre(name: 'helpshoe'); shoegaze.set_parent!(indie)
    genre(name: 'helppolka') # unrelated

    names = genre_subtree_names(rock.name)

    assert_includes names, rock.name
    assert_includes names, indie.name
    assert_includes names, shoegaze.name
    refute(names.any? { |n| n.start_with?('helppolka') })
  end

  test 'filter_terms_matching(g) lights a genre sitting under an applied ancestor' do
    rock = genre(name: 'litrock')
    shoegaze = genre(name: 'litshoe'); shoegaze.set_parent!(rock)
    jazz = genre(name: 'litjazz')

    # Filtering by the ancestor "litrock" lights the descendant tag "litshoe"...
    assert_equal [rock.name], filter_terms_matching([rock.name], shoegaze.name, param: 'g')
    # ...and tapping the genre itself lights it (self is in its own subtree).
    assert_equal [rock.name], filter_terms_matching([rock.name], rock.name, param: 'g')
    # An unrelated applied genre does not light it.
    assert_empty filter_terms_matching([jazz.name], shoegaze.name, param: 'g')
  end
end
