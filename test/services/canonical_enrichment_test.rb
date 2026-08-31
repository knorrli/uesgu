require "db_test_helper"

class CanonicalEnrichmentTest < ActiveSupport::TestCase
  def enrich(canonical, *duplicates) = CanonicalEnrichment.call(canonical, duplicates)

  test "fills a description the canonical does not have" do
    canonical = event(description: nil)
    enrich(canonical, event(description: "Support: Zorpband"))

    assert_equal "Support: Zorpband", canonical.reload.description
  end

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

  test "never takes the duplicate's url" do
    canonical = event(url: nil)
    enrich(canonical, event(url: "https://fixture.test/dup"))

    assert_nil canonical.reload.url
  end
end
