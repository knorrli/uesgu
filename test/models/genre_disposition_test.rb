require 'db_test_helper'

# Locks the disposition state machine on Genre: ignore!, hide!, block!, restore!,
# set_parent! and the visibility they re-derive on events. These are pure
# mechanics — the curation behaviour the app is built on — so they're tested with
# invented genre names and never reference real taxonomy content (which the
# parallel session is rewriting).
class GenreDispositionTest < ActiveSupport::TestCase
  test 'set_parent! files the genre and clears any prior disposition' do
    root = genre(events_count: 3)
    g = genre(events_count: 3)
    g.ignore!

    g.set_parent!(root)

    assert g.placed?
    assert_equal root.id, g.reload.parent_id
    refute g.ignored?
    refute g.hidden?
    refute g.blocked?
  end

  test 'ignore! marks the genre ignored and detaches it from the tree' do
    root = genre
    g = genre(parent: root)
    assert g.placed?

    g.ignore!

    refute g.placed?
    assert g.ignored?
  end

  test 'hide! hides an event whose only genre is the hidden one' do
    g = genre(name: 'poetry-slam')
    event = event_with_genres(g.name)
    event.recompute_visibility!
    refute event.reload.hidden

    g.hide!

    assert g.hidden?
    assert event.reload.hidden, 'non-music event drops out of public listings'
  end

  test 'hide! keeps an event visible when another genre is non-hidden' do
    music = genre(name: 'glimmercore')
    spoken = genre(name: 'lecture')
    event = event_with_genres(music.name, spoken.name)
    event.recompute_visibility!

    spoken.hide!

    refute event.reload.hidden, 'any non-hidden genre keeps the event visible'
  end

  test 'block! strips the genre tagging off events but keeps the event visible' do
    noise = genre(name: 'us') # scraper noise, e.g. a country code
    real = genre(name: 'indie')
    event = event_with_genres(noise.name, real.name)
    event.recompute_visibility!
    assert_includes event.reload.genre_list, noise.name

    noise.block!

    assert noise.blocked?
    refute_includes event.reload.genre_list, noise.name
    assert_includes event.genre_list, real.name, 'the real genre is untouched'
    refute event.hidden, 'the event itself stays visible'
    assert_equal 0, noise.reload.events_count
  end

  test 'block! keeps the genre out on the next scrape via genre_list=' do
    noise = genre(name: 'au')
    noise.block!

    fresh = event_with_genres(noise.name, 'techno-ish')

    refute_includes fresh.reload.genre_list, noise.name
    assert_includes fresh.genre_list, 'Techno-Ish' # survivor stored canonicalized
  end

  test 'restore! lifts every disposition mark and un-hides events' do
    g = genre(name: 'spoken-word')
    event = event_with_genres(g.name)
    event.recompute_visibility!
    g.hide!
    assert event.reload.hidden

    g.restore!

    refute g.ignored?
    refute g.hidden?
    refute g.blocked?
    refute event.reload.hidden, 'un-hiding re-derives the event as visible'
  end
end
