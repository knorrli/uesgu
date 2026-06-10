require 'db_test_helper'

# Locks Event's style-derivation mechanics: recompute_styles! projects the union
# of each genre's styles onto the event, sets the non-music `hidden` flag, and
# ensures a Genre row exists per tag; genre_list= drops blocklisted genres at the
# source. Mechanics only — invented genre/style names throughout.
class EventStylesTest < ActiveSupport::TestCase
  test 'recompute_styles! projects the union of the genres styles' do
    rock = style(name: 'wubrock')
    jazz = style(name: 'flarejazz')
    g1 = genre(name: 'genre-a', styles: [rock])
    g2 = genre(name: 'genre-b', styles: [jazz])
    event = event_with_genres(g1.name, g2.name)

    event.recompute_styles!

    assert_equal [rock.name, jazz.name].sort, event.reload.style_list.sort
  end

  test 'recompute_styles! de-duplicates when several genres share a style' do
    shared = style(name: 'glimmercore')
    g1 = genre(name: 'genre-c', styles: [shared])
    g2 = genre(name: 'genre-d', styles: [shared])
    event = event_with_genres(g1.name, g2.name)

    event.recompute_styles!

    assert_equal [shared.name], event.reload.style_list
  end

  test 'recompute_styles! matches genres case-insensitively' do
    s = style
    g = genre(name: 'lowgenre', styles: [s])
    event = event_with_genres(g.name.upcase) # scraped casing differs from the row

    event.recompute_styles!

    assert_equal [s.name], event.reload.style_list
  end

  test 'recompute_styles! creates a Genre row for every tag (ensure!)' do
    event = event_with_genres('never-seen-genre')
    assert_not genre_for('never-seen-genre')

    event.recompute_styles!

    assert genre_for('never-seen-genre')
  end

  test 'recompute_styles! leaves a fully-mapped event visible' do
    g = genre(styles: [style])
    event = event_with_genres(g.name)

    event.recompute_styles!

    refute event.reload.hidden
  end

  test 'recompute_styles! hides a non-music event: a hidden genre and no style' do
    g = genre(name: 'spoken-word')
    g.hide!
    event = event_with_genres(g.name)

    event.recompute_styles!

    assert event.reload.hidden
  end

  test 'a real style wins: an event keeps visible when a music genre coexists with a hidden one' do
    lecture = genre(name: 'lecture')
    lecture.hide!
    band = genre(name: 'liveband', styles: [style(name: 'postcore')])
    event = event_with_genres(lecture.name, band.name)

    event.recompute_styles!

    refute event.reload.hidden, 'a real style always wins'
  end

  test 'hidden_by_genre? flags non-music from the in-memory lists (the scrape path)' do
    g = genre(name: 'asmr')
    g.hide!
    event = event(genre_list: [g.name]) # no style assigned, as a fresh scrape would be

    assert event.hidden_by_genre?

    event.style_list = [style(name: 'drone').name]
    refute event.hidden_by_genre?, 'a real style always wins'
  end

  test 'genre_list= strips blocklisted genres case-insensitively at tagging time' do
    blocked = Genre.create!(name: 'JunkTag')
    blocked.block!

    event = event_with_genres('junktag', 'kept-genre') # lower-case variant of blocked

    # The blocked variant is stripped; the survivor is stored canonicalized.
    assert_equal ['Kept-Genre'], event.reload.genre_list
  end

  test 'genre_list= keeps everything when no genres are blocked' do
    event = event_with_genres('alpha', 'beta')

    assert_equal %w[Alpha Beta].sort, event.reload.genre_list.sort
  end
end
