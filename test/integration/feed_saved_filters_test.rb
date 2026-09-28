require "db_test_helper"

class FeedSavedFiltersTest < ActionDispatch::IntegrationTest
  setup do
    @listener = sign_in_as user(locale: "en")
  end

  test "saving from the feed creates the filter with the default schedule and lands on the feed as saved" do
    assert_difference -> { @listener.saved_filters.count }, 1 do
      post feed_saved_filters_path(g: ["Rock"], l: ["Bern"])
    end

    rule = @listener.saved_filters.last
    assert_equal ["Rock"], rule.genres
    assert_equal ["Bern"], rule.location_list
    assert_equal "daily", rule.cadence
    assert_equal 1080, rule.time_of_day
    assert rule.notify_in_app?
    refute rule.notify_push?
    refute rule.notify_email?

    land_on_feed
    assert_select "a.filter-menu__save.is-saved[href=?]", edit_saved_filter_path(rule)
    assert_equal rule, applied
  end

  test "saving an empty feed creates the notify-on-everything filter" do
    assert_difference -> { @listener.saved_filters.count }, 1 do
      post feed_saved_filters_path
    end

    rule = @listener.saved_filters.last
    assert_empty rule.queries + rule.genres + rule.location_list + rule.date_ranges
    land_on_feed
    assert_select "a.filter-menu__save.is-saved"
  end

  test "saving criteria you already have lands on the existing filter without a duplicate" do
    existing = saved_filter(g: ["Rock"])

    assert_no_difference -> { @listener.saved_filters.count } do
      post feed_saved_filters_path(g: ["Rock"])
    end

    land_on_feed
    assert_select "a.filter-menu__save.is-saved[href=?]", edit_saved_filter_path(existing)
  end

  test "updating from the feed rewrites the criteria and keeps the schedule and channels" do
    rock = saved_filter(g: ["Rock"])
    rock.update!(cadence: "weekly", weekday: 2, notify_push: true)

    patch feed_saved_filter_path(rock, g: ["Rock", "Pop"])

    rock.reload
    assert_equal ["Rock", "Pop"], rock.genres
    assert_equal "weekly", rock.cadence
    assert_equal 2, rock.weekday
    assert_equal 540, rock.time_of_day
    assert rock.notify_push?

    land_on_feed
    assert_select "a.filter-menu__save.is-saved[href=?]", edit_saved_filter_path(rock)
    assert_equal rock, applied
  end

  test "updating into criteria another filter already has leaves both alone and lands on that one" do
    rock = saved_filter(g: ["Rock"])
    pop = saved_filter(g: ["Pop"])

    patch feed_saved_filter_path(rock, g: ["Pop"])

    assert_equal ["Rock"], rock.reload.genres
    land_on_feed
    assert_select "a.filter-menu__save.is-saved[href=?]", edit_saved_filter_path(pop)
    assert_equal pop, applied
  end

  test "updating only reaches your own filters" do
    stranger = user.saved_filters.new(cadence: "daily", time_of_day: 540)
    stranger.filter_attributes = { g: ["Rock"] }
    stranger.save!

    patch feed_saved_filter_path(stranger, g: ["Pop"])

    assert_response :not_found
    assert_equal ["Rock"], stranger.reload.genres
  end

  private

  def saved_filter(**criteria)
    @listener.saved_filters.new(cadence: "daily", time_of_day: 540).tap do |rule|
      rule.filter_attributes = criteria
      rule.save!
    end
  end

  def land_on_feed
    follow_redirect! while response.redirect?
    assert_response :success
  end

  def applied
    @listener.sessions.sole.reload.applied_saved_filter
  end
end
