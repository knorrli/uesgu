require 'db_test_helper'

# Locks StyleSuggester's two ranked signals for guessing an unmapped genre's
# styles: (1) co-occurrence — styles already on the events that carry the genre,
# strongest first by frequency; (2) name similarity — styles of the most
# Levenshtein-similar mapped genres. Synthetic names only.
class StyleSuggesterTest < ActiveSupport::TestCase
  test 'suggests styles that co-occur on the events carrying the genre' do
    target = genre(name: 'mystery')          # unmapped genre we want to classify
    cooccurring = style(name: 'wubstep')
    e = event_with_genres(target.name)
    e.update!(style_list: [cooccurring.name]) # style contributed by other genres

    suggestions = StyleSuggester.call(target)

    assert_includes suggestions, cooccurring
  end

  test 'co-occurring styles are ranked by frequency, most common first' do
    target = genre(name: 'ambiguous')
    common = style(name: 'common')
    rare = style(name: 'rare')
    2.times do
      e = event_with_genres(target.name)
      e.update!(style_list: [common.name])
    end
    e = event_with_genres(target.name)
    e.update!(style_list: [rare.name])

    suggestions = StyleSuggester.call(target)

    assert_equal common, suggestions.first
    assert_includes suggestions, rare
  end

  test 'falls back to styles of name-similar mapped genres' do
    similar_style = style(name: 'glimmercore')
    genre(name: 'technoo', styles: [similar_style]) # assigned + name-similar
    target = genre(name: 'techno')                  # unmapped, on no events

    suggestions = StyleSuggester.call(target)

    assert_includes suggestions, similar_style
  end

  test 'respects the limit' do
    target = genre(name: 'capped')
    3.times do |i|
      s = style(name: "s#{i}")
      e = event_with_genres(target.name)
      e.update!(style_list: [s.name])
    end

    assert_operator StyleSuggester.call(target, limit: 2).size, :<=, 2
  end

  test 'returns nothing for a genre with no events and no peers' do
    assert_empty StyleSuggester.call(genre(name: 'island'))
  end
end
