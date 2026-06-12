require 'db_test_helper'

# Locks CalendarHelper#calendar_day_venues — the per-cell venue summary: group a
# day's events by venue (falling back to the first location), dedupe with a
# count, drop blanks, and sort favorites-first, then busiest, then alphabetical.
# Plus the namespaced favorite-key list driving each cell's heart marker.
# Synthetic location/style names (not real venues, so `venue` falls back to the
# first location tag — deterministic and scraper-independent).
class CalendarHelperTest < ActionView::TestCase
  test 'groups events by venue with a count, busiest first' do
    events = [
      event(location_list: ['Aula']),
      event(location_list: ['Aula']),
      event(location_list: ['Beisl'])
    ]

    result = calendar_day_venues(events)

    assert_equal %w[Aula Beisl], result.map(&:name), 'busiest venue leads'
    by_name = result.index_by(&:name)
    assert_equal 2, by_name['Aula'].count
    assert_equal 1, by_name['Beisl'].count
    refute by_name['Aula'].favorite
  end

  test 'favorited venues sort ahead of busier non-favorites' do
    events = [
      event(location_list: ['FavSpot']),
      event(location_list: ['BusySpot']),
      event(location_list: ['BusySpot']),
      event(location_list: ['BusySpot'])
    ]

    result = calendar_day_venues(events, favorites: ['FavSpot'])

    assert_equal 'FavSpot', result.first.name
    assert result.first.favorite
    assert_equal 3, result.last.count, 'the busier non-favorite still trails'
  end

  test 'ties break alphabetically by venue name' do
    events = [event(location_list: ['Zed']), event(location_list: ['Amy'])]

    assert_equal %w[Amy Zed], calendar_day_venues(events).map(&:name)
  end

  test 'events without any location are dropped' do
    events = [event(location_list: ['Aula']), event] # second has no location tags

    assert_equal ['Aula'], calendar_day_venues(events).map(&:name)
  end

  test 'calendar_day_load is zero for empty days and clamps at saturation' do
    assert_equal 0.0, calendar_day_load(0)
    assert_equal 0.0, calendar_day_load(-3)
    # A single event still tints (floored above zero), and the fraction rises with
    # the count until it saturates at 1.0 and stays there.
    assert_operator calendar_day_load(1), :>, 0.0
    assert_operator calendar_day_load(2), :>, calendar_day_load(1)
    assert_equal 1.0, calendar_day_load(CalendarHelper::CALENDAR_LOAD_SATURATION)
    assert_equal 1.0, calendar_day_load(CalendarHelper::CALENDAR_LOAD_SATURATION + 5)
  end

  test 'calendar_day_favorite_keys namespaces locations and styles, deduped' do
    a = event(location_list: ['Loc1'], style_list: ['Style1'])
    b = event(location_list: ['Loc1'], style_list: ['Style1']) # same tags

    keys = calendar_day_favorite_keys([a, b])

    assert_includes keys, 'l:Loc1'
    assert_includes keys, 's:Style1'
    assert_equal keys.uniq, keys, 'keys are de-duplicated across events'
  end
end
