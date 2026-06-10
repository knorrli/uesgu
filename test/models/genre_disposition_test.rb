require 'db_test_helper'

# Locks the disposition state machine on Genre: assign_styles!, ignore!, hide!,
# block!, restore! and the scopes that surface each disposition. These are pure
# mechanics — the curation behaviour the app is built on — so they're tested with
# invented genre/style names and never reference real taxonomy content (which the
# parallel session is rewriting).
class GenreDispositionTest < ActiveSupport::TestCase
  test 'assign_styles! maps the genre and clears any prior disposition' do
    g = genre(events_count: 3)
    g.ignore!
    s1 = style
    s2 = style

    g.assign_styles!([s1.id, s2.id])

    assert g.assigned?
    assert_equal [s1, s2].map(&:id).sort, g.reload.styles.pluck(:id).sort
    refute g.ignored?
    refute g.hidden?
    refute g.blocked?
  end

  test 'assign_styles! accepts the combobox comma-joined string form' do
    g = genre
    s1 = style
    s2 = style

    g.assign_styles!("#{s1.id},#{s2.id}")

    assert_equal [s1, s2].map(&:id).sort, g.reload.styles.pluck(:id).sort
  end

  test 'assign_styles! re-derives styles on events carrying the genre' do
    g = genre(name: 'flarejazz')
    s = style
    event = event_with_genres(g.name)
    event.recompute_styles!
    assert_empty event.reload.style_list, 'unmapped genre yields no styles'

    g.assign_styles!([s.id])

    assert_equal [s.name], event.reload.style_list
  end

  test 'ignore! clears styles and marks the genre ignored' do
    g = genre(styles: [style])
    assert g.assigned?

    g.ignore!

    refute g.assigned?
    assert g.ignored?
    assert_empty g.reload.styles
  end

  test 'hide! hides an event whose only genre is the hidden one' do
    g = genre(name: 'poetry-slam')
    event = event_with_genres(g.name)
    event.recompute_styles!
    refute event.reload.hidden

    g.hide!

    assert g.hidden?
    assert event.reload.hidden, 'non-music event drops out of public listings'
  end

  test 'hide! keeps an event visible when another genre maps to a music style' do
    music = genre(name: 'glimmercore', styles: [style])
    spoken = genre(name: 'lecture')
    event = event_with_genres(music.name, spoken.name)
    event.recompute_styles!

    spoken.hide!

    refute event.reload.hidden, 'a real style always wins over a hidden genre'
  end

  test 'block! strips the genre tagging off events but keeps the event visible' do
    noise = genre(name: 'us') # scraper noise, e.g. a country code
    real = genre(name: 'indie', styles: [style])
    event = event_with_genres(noise.name, real.name)
    event.recompute_styles!
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
    event.recompute_styles!
    g.hide!
    assert event.reload.hidden

    g.restore!

    refute g.ignored?
    refute g.hidden?
    refute g.blocked?
    refute event.reload.hidden, 'un-hiding re-derives the event as visible'
  end
end
