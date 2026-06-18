require 'db_test_helper'

# Locks CalendarHelper#calendar_day_venues — the per-cell venue summary: group a
# day's events by venue (falling back to the first location), dedupe with a
# count, drop blanks, and sort favorites-first, then busiest, then alphabetical.
# Plus the namespaced favorite-key list driving each cell's heart marker.
# Synthetic location/style names (not real venues, so `venue` falls back to the
# first location tag — deterministic and scraper-independent).
class CalendarHelperTest < ActionView::TestCase
  # calendar_day_headline leans on EventsHelper (event_saved?, event_matches_follow?);
  # in the app every helper shares one view context, so pull it in here too.
  include EventsHelper

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

  # --- calendar_day_headline: up to two venues + a "+N more" overflow count. ---
  # Saved/follow state is read via the EventsHelper memo ivars, so we seed those
  # directly instead of standing up a session + current_user.

  test 'headline names up to two saved venues and spills the rest into extra' do
    saved = [
      event(location_list: ['Aula']),
      event(location_list: ['Beisl']),
      event(location_list: ['Cano']),
      event(location_list: ['Cano']) # duplicate venue collapses, not counted twice
    ]
    @saved_event_ids = Set.new(saved.map(&:id))

    headline = calendar_day_headline(saved)

    assert_equal %w[Aula Beisl], headline.venues
    assert_equal 1, headline.extra, 'three distinct venues → two named + 1 more'
  end

  test 'headline has no overflow when two or fewer saved venues' do
    saved = [event(location_list: ['Aula']), event(location_list: ['Beisl'])]
    @saved_event_ids = Set.new(saved.map(&:id))

    headline = calendar_day_headline(saved)

    assert_equal %w[Aula Beisl], headline.venues
    assert_equal 0, headline.extra
  end

  test 'headline falls back to followed venues when nothing is saved' do
    @saved_event_ids = Set.new
    @followed_locations = Set.new(['Aula'])
    events = [event(location_list: ['Aula']), event(location_list: ['Ignored'])]

    headline = calendar_day_headline(events)

    assert_equal ['Aula'], headline.venues, 'only follow-matching events headline'
    assert_equal 0, headline.extra
  end

  test 'headline is nil on a day with no saved or followed events' do
    @saved_event_ids = Set.new
    @followed_locations = Set.new
    @followed_styles = Set.new

    assert_nil calendar_day_headline([event(location_list: ['Aula'])])
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
