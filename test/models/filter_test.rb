require 'db_test_helper'

# Locks the Filter query object: how request params parse into tag lists, the
# shape of the ransack query it builds, date-range preset ordering, and the
# earliest-date resolution used to jump the calendar.
class FilterTest < ActiveSupport::TestCase
  test 'list setters parse a comma string into a tag array' do
    f = Filter.new
    f.queries = 'rock, jazz'
    f.genres = 'wubstep, glimmercore'

    assert_equal %w[rock jazz], f.queries
    assert_equal %w[wubstep glimmercore], f.genres
  end

  test 'build sets the lists it is given and leaves nil ones at their default' do
    f = Filter.build(queries: 'rock', genres: %w[techno], location_list: nil)

    assert_equal %w[rock], f.queries
    assert_equal %w[techno], f.genres
    assert_empty f.location_list, 'a nil list is left at its empty default'
    assert_empty f.date_ranges, 'an omitted list is left at its empty default'
  end

  test 'build runs each value through the same parsing as the setters' do
    f = Filter.build(queries: 'rock, jazz', date_ranges: %w[next_week today])

    assert_equal %w[rock jazz], f.queries, 'comma string parses to a tag array'
    assert_equal %w[today next_week], f.date_ranges, 'presets sort into preset order'
  end

  test 'date_ranges are ordered by the datepicker preset sequence' do
    f = Filter.new
    f.date_ranges = %w[next_week today] # given out of order

    assert_equal %w[today next_week], f.date_ranges,
                 'presets sort into Datepicker.preset key order'
  end

  test 'unknown date ranges sort after the known presets' do
    f = Filter.new
    f.date_ranges = ['2030-01-01 - 2030-01-31', 'today']

    assert_equal 'today', f.date_ranges.first
  end

  test 'ransack_query defaults to upcoming events when no date range is set' do
    f = Filter.new
    group = f.ransack_query[:g]
    date_group = group.find { |h| h.key?(:start_date_gteq) || h.key?(:start_date_between_any) }

    assert_equal Date.current.beginning_of_day, date_group[:start_date_gteq]
  end

  test 'ransack_query maps a date preset into a concrete between range' do
    f = Filter.new
    f.date_ranges = ['today']
    date_group = f.ransack_query[:g].find { |h| h.key?(:start_date_between_any) }

    assert date_group, 'a between range is emitted when a preset is active'
    assert_includes date_group[:start_date_between_any].first, Date.current.iso8601
  end

  test 'a named preset keeps the future floor; an explicit absolute range drops it' do
    preset = Filter.build(date_ranges: ['this_month']).ransack_query[:g]
              .find { |h| h.key?(:start_date_between_any) }
    assert_equal Date.current.beginning_of_day, preset[:start_date_gteq],
                 'a preset window still hides past events'

    custom = Filter.build(date_ranges: ['2020-01-01 - 2020-12-31']).ransack_query[:g]
              .find { |h| h.key?(:start_date_between_any) }
    refute custom.key?(:start_date_gteq),
           'an explicitly typed absolute range reveals past events'
  end

  test 'earliest_date resolves the soonest concrete date across presets' do
    f = Filter.new
    f.date_ranges = ['today']
    assert_equal Date.current, f.earliest_date
  end

  test 'earliest_date is nil when no date filter is active' do
    assert_nil Filter.new.earliest_date
  end

  test 'genres makes the filter active' do
    assert Filter.build(genres: %w[anything]).active?
  end

  test 'expanded_genre_names returns the picked genre plus every descendant' do
    rock = genre(name: 'filterrock')
    indie = genre(name: 'filterindie'); indie.set_parent!(rock)
    shoegaze = genre(name: 'filtershoegaze'); shoegaze.set_parent!(indie)
    genre(name: 'filterpolka') # unrelated sibling tree

    names = Filter.build(genres: [rock.name]).expanded_genre_names.sort

    assert_equal [rock.name, indie.name, shoegaze.name].sort, names
  end

  test 'expanded_genre_names is empty with no genres picked' do
    assert_empty Filter.new.expanded_genre_names
  end

  test 'filtering by a genre matches events tagged with any descendant' do
    rock = genre(name: 'matchrock')
    shoegaze = genre(name: 'matchshoegaze'); shoegaze.set_parent!(rock)
    hit = event_with_genres(shoegaze.name)        # tagged only with the descendant
    miss = event_with_genres(genre(name: 'matchpolka').name)

    ids = Event.ransack(Filter.build(genres: [rock.name]).ransack_query).result.ids

    assert_includes ids, hit.id, 'an ancestor pick catches a descendant-tagged event'
    refute_includes ids, miss.id
  end

  test 'an aliased token is preserved on the event yet still matches its canonical filter' do
    electronic = genre(name: 'aliaselectronic')
    elektronik = genre(name: 'aliaselektronik'); elektronik.merge_into!(electronic)
    event = event_with_genres(elektronik.name)

    # Source-data integrity: ingest keeps the raw alias token, never rewrites it to
    # the canonical (match-not-rewrite).
    assert_includes event.reload.genre_list, elektronik.name
    refute_includes event.genre_list, electronic.name

    # …yet a filter on the canonical expands to, and matches, that raw token.
    assert_includes Filter.build(genres: [electronic.name]).expanded_genre_names, elektronik.name
    ids = Event.ransack(Filter.build(genres: [electronic.name]).ransack_query).result.ids
    assert_includes ids, event.id, 'the canonical filter catches the raw-aliased event'
  end
end
