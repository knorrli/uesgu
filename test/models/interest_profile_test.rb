require "db_test_helper"

# InterestProfile derives "what could interest me" from a user's saved filters:
# a date-stripped, whole-filter match used to highlight the list/calendar.
# Synthetic taxonomy only (see db_test_helper taxonomy rule).
class InterestProfileTest < ActiveSupport::TestCase
  # Build + persist a saved filter from landing-page params (q/g/l/d).
  def saved(owner, **filter)
    rule = owner.saved_filters.new(cadence: "daily", time_of_day: 18 * 60, weekday: 1, monthday: 1,
                                   notify_in_app: false, notify_push: false, notify_email: false)
    rule.filter_attributes = filter
    rule.save!
    rule
  end

  test "no user → empty profile, nothing interests" do
    profile = InterestProfile.for(nil)
    assert_not profile.any?
    assert_not profile.interesting?(event_with_genres("zap-rock"))
  end

  test "a genre filter matches the genre and its whole subtree" do
    parent = genre(name: "rock")
    child  = genre(name: "shoegaze", parent: parent)
    u = user
    saved(u, g: [parent.name])

    hit  = event_with_genres(child.name)   # tagged a descendant of the filtered genre
    miss = event_with_genres(genre(name: "techno").name)

    profile = InterestProfile.for(u)
    assert profile.interesting?(hit)
    assert_not profile.interesting?(miss)
    assert_equal [child.name], profile.why_genres(hit).map(&:name)
  end

  test "why_genres flags only the genres that explain the match" do
    parent = genre(name: "rock")
    child  = genre(name: "grunge", parent: parent)
    other  = genre(name: "jazz")
    u = user
    saved(u, g: [parent.name])

    e = event_with_genres(child.name, other.name)
    assert_equal [child.name], InterestProfile.for(u).why_genres(e).map(&:name)
  end

  test "a location-only filter matches by venue and flags it" do
    u = user
    saved(u, l: ["Dachstock"])

    here  = event(location_list: ["Dachstock"])
    there = event(location_list: ["ISC Club"])

    profile = InterestProfile.for(u)
    assert profile.interesting?(here)
    assert_not profile.interesting?(there)
    assert_equal ["Dachstock"], profile.why_locations(here).map(&:name)
  end

  test "a free-text filter matches a CONTAINS on title" do
    u = user
    saved(u, q: ["carner"])

    assert InterestProfile.for(u).interesting?(event(title: "Loyle Carner live"))
    assert_not InterestProfile.for(u).interesting?(event(title: "Some Other Act"))
  end

  test "whole-filter match: genre AND location must both hold" do
    g = genre(name: "hiphop")
    u = user
    saved(u, g: [g.name], l: ["Bern"])

    both  = event(location_list: ["Bern"], genre_list: [g.name])
    wrong_place = event(location_list: ["Zürich"], genre_list: [g.name])

    profile = InterestProfile.for(u)
    assert profile.interesting?(both)
    assert_not profile.interesting?(wrong_place), "genre alone must not match a genre+location filter"
  end

  test "the date window is ignored (taste only)" do
    g = genre(name: "klassik")
    u = user
    # A "happening this weekend" filter — InterestProfile must match on taste
    # regardless of the event's date or the window.
    saved(u, g: [g.name], d: ["this_weekend"])

    far_future = event(genre_list: [g.name], start_date: Date.new(2099, 1, 1))
    assert InterestProfile.for(u).interesting?(far_future)
  end

  test "a pure date-window filter carries no taste and is ignored" do
    u = user
    saved(u, d: ["this_week"])

    profile = InterestProfile.for(u)
    assert_not profile.any?
    assert_not profile.interesting?(event_with_genres("anything"))
  end

  test "a filter with the highlight toggle off is skipped entirely" do
    g = genre(name: "dubwave")
    u = user
    saved(u, g: [g.name]).update!(highlight_in_feed: false)

    profile = InterestProfile.for(u)
    assert_not profile.any?
    assert_not profile.interesting?(event_with_genres(g.name))
  end

  test "the highlight toggle is per-filter: an off filter doesn't dim the others" do
    on  = genre(name: "zapcore")
    off = genre(name: "quietwave")
    u = user
    saved(u, g: [on.name])
    saved(u, g: [off.name]).update!(highlight_in_feed: false)

    profile = InterestProfile.for(u)
    assert profile.interesting?(event_with_genres(on.name))
    assert_not profile.interesting?(event_with_genres(off.name))
  end
end
