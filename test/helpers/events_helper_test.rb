require "db_test_helper"

# Locks EventsHelper's predicate/URL logic (the fiddly bits that break silently):
# calendar nav URL surgery and the genre-subtree descendant highlight.
class EventsHelperTest < ActionView::TestCase
  # The helper resolves current_user via the controller; provide it for the test.
  attr_writer :current_user
  def current_user = @current_user

  test "calendar_nav_path drops the open day but preserves the filter" do
    result = calendar_nav_path("http://test.host/events?view=calendar&day=2030-01-01&l%5B%5D=Venue")
    query = Rack::Utils.parse_nested_query(URI.parse(result).query)

    refute query.key?("day"), "changing months collapses the open day"
    assert_equal "calendar", query["view"]
    assert_equal ["Venue"], query["l"]
  end

  test "calendar_nav_path clears the query entirely when only the day was set" do
    result = calendar_nav_path("http://test.host/events?day=2030-01-01")
    assert_nil URI.parse(result).query
  end

  test "genre_subtree_names returns the genre plus every descendant" do
    rock = genre(name: "helprock")
    indie = genre(name: "helpindie"); indie.set_parent!(rock)
    shoegaze = genre(name: "helpshoe"); shoegaze.set_parent!(indie)
    genre(name: "helppolka") # unrelated

    names = genre_subtree_names(rock.name)

    assert_includes names, rock.name
    assert_includes names, indie.name
    assert_includes names, shoegaze.name
    refute(names.any? { |n| n.start_with?("helppolka") })
  end

  test "filter_terms_matching(g) lights a genre sitting under an applied ancestor" do
    rock = genre(name: "litrock")
    shoegaze = genre(name: "litshoe"); shoegaze.set_parent!(rock)
    jazz = genre(name: "litjazz")

    # Filtering by the ancestor "litrock" lights the descendant tag "litshoe"...
    assert_equal [rock.name], filter_terms_matching([rock.name], shoegaze.name, param: "g")
    # ...and tapping the genre itself lights it (self is in its own subtree).
    assert_equal [rock.name], filter_terms_matching([rock.name], rock.name, param: "g")
    # An unrelated applied genre does not light it.
    assert_empty filter_terms_matching([jazz.name], shoegaze.name, param: "g")
  end

  test "a raw aliased tag lights under its canonical filter (match and highlight stay in sync)" do
    electronic = genre(name: "lithelpelectronic")
    elektronik = genre(name: "lithelpelektronik"); elektronik.merge_into!(electronic)

    # Filtering by "Electronic" lights the raw "Elektronik" tag the event carries.
    assert_equal [electronic.name], filter_terms_matching([electronic.name], elektronik.name, param: "g")
  end
end
