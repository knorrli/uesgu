require "db_test_helper"

# Locks EventsHelper's predicate/URL logic (the fiddly bits that break silently):
# offsite-link badging and the genre-subtree descendant highlight.
class EventsHelperTest < ActionView::TestCase
  # The helper resolves current_user via the controller; provide it for the test.
  attr_writer :current_user
  def current_user = @current_user

  test "event_offsite_source badges a listing or social host, but not the venue's own page" do
    assert_equal "Bewegungsmelder", event_offsite_source(event(url: "https://www.bewegungsmelder.ch/e/1"))
    assert_equal "Instagram", event_offsite_source(event(url: "https://instagram.com/p/abc"))
    assert_equal "Facebook", event_offsite_source(event(url: "https://m.facebook.com/events/1"))
    assert_nil event_offsite_source(event(url: "https://venue.test/show"))
  end

  test "event_offsite_source is nil for a captured event with no url" do
    assert_nil event_offsite_source(event(url: nil))
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
