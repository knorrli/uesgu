require "db_test_helper"

# What a canonical takes from the duplicates folded onto it. The point of every case
# here is that it FILLS rather than overwrites: that is what lets a capture enrich a
# scraped listing without pinning the field, because the scraper re-sets its own value
# from source before this runs again. Invented genre names (taxonomy rule).
class CanonicalEnrichmentTest < ActiveSupport::TestCase
  def enrich(canonical, *duplicates) = CanonicalEnrichment.call(canonical, duplicates)

  test "fills a description the canonical does not have" do
    canonical = event(description: nil)
    enrich(canonical, event(description: "Support: Zorpband"))

    assert_equal "Support: Zorpband", canonical.reload.description
  end

  # The whole reason nothing is pinned: the scraper's own value has to keep winning,
  # or a venue publishing a real description next week would never land.
  test "leaves a description the canonical already has" do
    canonical = event(description: "From the venue")
    enrich(canonical, event(description: "From a poster"))

    assert_equal "From the venue", canonical.reload.description
  end

  test "fills a start time the canonical does not have" do
    at_nine = Time.zone.parse("#{Date.current + 3} 21:00")
    canonical = event(start_date: Date.current + 3, start_time: nil)
    enrich(canonical, event(start_date: Date.current + 3, start_time: at_nine))

    assert_equal at_nine, canonical.reload.start_time
  end

  test "unions the duplicates' genres onto the canonical" do
    canonical = event
    canonical.genre_list = ["zorpcore"]
    canonical.save!
    duplicate = event
    duplicate.genre_list = ["zorpwave"]
    duplicate.save!

    enrich(canonical, duplicate)

    assert_equal %w[zorpcore zorpwave], canonical.reload.genre_list.map(&:downcase).sort
  end

  # Visibility is a projection of the genres that now stand, so a genre read off a
  # poster can lift the music gate off a listing whose own genres had hidden it.
  test "a duplicate's music genre lifts the music gate" do
    hidden_genre = genre(name: "zorpsport")
    hidden_genre.update!(hidden_at: Time.current)
    canonical = event
    canonical.genre_list = [hidden_genre.name]
    canonical.save!
    canonical.recompute_visibility!
    assert_predicate canonical.reload, :hidden?

    duplicate = event
    duplicate.genre_list = ["zorpjazz"]
    duplicate.save!
    enrich(canonical, duplicate)

    refute_predicate canonical.reload, :hidden?
  end

  test "changes nothing when the duplicates add nothing" do
    canonical = event(description: "From the venue")
    before = canonical.updated_at
    enrich(canonical, event(description: nil))

    assert_equal before, canonical.reload.updated_at
  end

  test "no duplicates is a no-op" do
    canonical = event(description: nil)
    before = canonical.updated_at
    CanonicalEnrichment.call(canonical, [])

    assert_equal before, canonical.reload.updated_at
  end

  # `url` is the scrapers' upsert key under a unique index: copying one across would
  # strand the row it came from on the next run.
  test "never takes the duplicate's url" do
    canonical = event(url: nil)
    enrich(canonical, event(url: "https://fixture.test/dup"))

    assert_nil canonical.reload.url
  end
end
