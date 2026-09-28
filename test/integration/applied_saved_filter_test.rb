require "db_test_helper"

class AppliedSavedFilterTest < ActionDispatch::IntegrationTest
  setup do
    @listener = sign_in_as user(locale: "en")
    @rock = saved_filter(g: ["Rock"])
  end

  test "applying a saved filter remembers it and lands on a clean URL" do
    get events_path(g: ["Rock"], applied: @rock.id, filtered: 1)

    assert_redirected_to events_path(g: ["Rock"])
    assert_equal @rock, applied
  end

  test "after changing the applied filter, the menu offers to update it with the new criteria" do
    apply @rock

    get events_path(g: ["Rock", "Pop"])

    assert_select "a.filter-menu__save[href=?]", new_saved_filter_path(g: ["Rock", "Pop"])
    assert_select "a.filter-menu__update[href=?]", edit_saved_filter_path(@rock, g: ["Rock", "Pop"]),
                  text: "Update “#{@rock.display_name}”"
  end

  test "while the feed still matches the applied filter there is nothing to update" do
    apply @rock

    get events_path(g: ["Rock"])

    assert_select "a.filter-menu__save.is-saved"
    assert_select "a.filter-menu__update", false
  end

  test "the edit form opens with the criteria carried from the feed" do
    get edit_saved_filter_path(@rock, g: ["Rock", "Pop"])

    assert_response :success
    assert_select "input[name='g[]'][value=?][checked]", "Pop"
    assert_equal ["Rock"], @rock.reload.genres
  end

  test "saving the applied filter forgets it" do
    apply @rock

    patch saved_filter_path(@rock), params: { g: ["Rock", "Pop"] }

    assert_equal ["Rock", "Pop"], @rock.reload.genres
    assert_nil applied
  end

  test "saving a different filter keeps the applied one" do
    jazz = saved_filter(g: ["Jazz"])
    apply @rock

    patch saved_filter_path(jazz), params: { g: ["Jazz", "Soul"] }

    assert_equal @rock, applied
  end

  test "applying another saved filter replaces the remembered one" do
    jazz = saved_filter(g: ["Jazz"])
    apply @rock

    apply jazz

    assert_equal jazz, applied
  end

  test "clearing the filter forgets it" do
    apply @rock

    get events_path(filtered: 1)

    assert_nil applied
  end

  test "adjusting the filter keeps it" do
    apply @rock

    get events_path(g: ["Rock", "Pop"], filtered: 1)

    assert_equal @rock, applied
  end

  test "deleting the applied filter forgets it" do
    apply @rock

    delete saved_filter_path(@rock)

    assert_nil applied
  end

  test "someone else's filter is never remembered" do
    stranger = user.saved_filters.new(cadence: "daily", time_of_day: 540)
    stranger.filter_attributes = { g: ["Rock"] }
    stranger.save!

    get events_path(g: ["Rock"], applied: stranger.id, filtered: 1)

    assert_nil applied
  end

  test "the saved-filters page applies a filter the same way" do
    get saved_filters_path

    assert_select "a[href=?]", events_path(q: [], g: ["Rock"], l: [], d: [], applied: @rock.id, filtered: 1)
  end

  private

  def saved_filter(**criteria)
    @listener.saved_filters.new(cadence: "daily", time_of_day: 540).tap do |rule|
      rule.filter_attributes = criteria
      rule.save!
    end
  end

  def apply(rule)
    get events_path(g: rule.genres, applied: rule.id, filtered: 1)
  end

  def applied
    @listener.sessions.sole.reload.applied_saved_filter
  end
end
