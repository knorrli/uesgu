require_relative "../db_test_helper"

# Word-overlap suggestions for the curation queue: filing a novel compound genre
# should surface the existing genres nested inside it (the tighter parent / merge
# target) that Levenshtein distance never relates. Synthetic taxonomy only.
#
# These create genres with EXACT names (not the `genre` fixture, which appends a
# "-<seq>" uniquifier) because the whole point under test is fingerprint
# substring/containment — a suffix would poison those relationships.
class RelatedGenreSuggesterTest < ActiveSupport::TestCase
  def mk(name, events_count: 1)
    Genre.create!(name:, events_count:)
  end

  test "surfaces existing genres that sit inside the new token, most-used first" do
    flarn = mk("Flarn", events_count: 1)
    wave  = mk("Wave", events_count: 9)

    related = RelatedGenreSuggester.call(mk("Flarnwave"))

    # Both are substrings of 'flarnwave'; the busier one leads.
    assert_equal [wave.id, flarn.id], related.map(&:id)
  end

  test "matches an existing genre that contains one of a multi-word name's words" do
    neo = mk("Neoflarn", events_count: 3) # contains the word 'flarn'

    related = RelatedGenreSuggester.call(mk("Flarn Crossover"))

    assert_includes related.map(&:id), neo.id
  end

  test "ranks a nested stem above a mere word-container" do
    stem = mk("Flarn", events_count: 1)      # substring of 'flarnwaveflarn'
    container = mk("Xflarnx", events_count: 9) # only contains the word 'flarn'

    related = RelatedGenreSuggester.call(mk("Flarnwave Flarn"))

    assert_equal stem.id, related.first.id, "the nested stem should outrank the word-container despite lower usage"
    assert_includes related.map(&:id), container.id
  end

  test "ignores itself, aliased/hidden/blocked genres, and sub-3-char genres" do
    subject = mk("Flarnwave")
    hidden = mk("Flarn"); hidden.hide!
    aliased = mk("Wave"); aliased.merge_into!(mk("Welle"))
    mk("Fl", events_count: 5) # too short to be a meaningful relative

    related = RelatedGenreSuggester.call(subject)

    refute_includes related.map(&:id), subject.id
    refute_includes related.map(&:id), hidden.id
    refute_includes related.map(&:id), aliased.id
    assert_empty related.select { |g| g.name == "Fl" }
  end

  test "honours the exclude list (the alias suggestions already shown)" do
    flarn = mk("Flarn")
    subject = mk("Flarnwave")

    assert_empty RelatedGenreSuggester.call(subject, exclude: [flarn.id])
  end

  test "returns nothing for a genre with no fingerprint" do
    assert_empty RelatedGenreSuggester.call(nil)
  end
end
