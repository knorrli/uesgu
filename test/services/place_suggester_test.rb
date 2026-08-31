require "db_test_helper"

# Match-at-entry: the near-name candidates the capture screen offers so a
# contributor taps an existing place instead of minting a fourth spelling of it.
# Synthetic place names throughout; the registry side is read live, never
# hardcoded.
class PlaceSuggesterTest < ActiveSupport::TestCase
  # The case that chose trigrams over edit distance: the extracted name is a
  # FRAGMENT of the stored one, which Levenshtein scores as wildly distant.
  test "an extracted fragment finds the fuller stored place" do
    quartierfest = place(name: "Marzili Quartierfest")

    assert_equal [quartierfest.name], names_for("Quartierfest")
  end

  # The same split in the other order — whichever spelling was captured first.
  test "an extracted fuller name finds the stored fragment" do
    place(name: "Quartierfest")

    assert_equal ["Quartierfest"], names_for("Marzili Quartierfest")
  end

  test "a typo still reaches the place it misspells" do
    place(name: "Zorpsaal")

    assert_includes names_for("Zorpsal"), "Zorpsaal"
  end

  # The whole point of the strict measure: "Bern" sits inside "Wabern" as a
  # substring but not as a word, and the loose form scores that pair at 0.6.
  test "a substring that is not a word is not a match" do
    place(name: "Wabern", locality: "Wabern")

    assert_empty names_for("Bern")
  end

  test "an unrelated name suggests nothing" do
    place(name: "Zorpsaal")

    assert_empty names_for("Blorpwerk")
    assert_empty names_for("")
  end

  # The most valuable outcome of match-at-entry is "this is actually Dachstock":
  # tag the event and write no Place row at all.
  test "candidates include registry venues, flagged as such" do
    venue = Venue.in_taxonomy.first
    skip "no venues in the taxonomy" if venue.nil?

    suggestion = PlaceSuggester.for_name(venue.name).first

    assert_equal venue.name, suggestion.name
    assert_predicate suggestion, :registry?
  end

  test "a captured place is not flagged as a registry venue" do
    place(name: "Zorpsaal")

    refute_predicate PlaceSuggester.for_name("Zorpsaal").first, :registry?
  end

  # The registry is keyed by domain, so a carried URL resolves exactly — even when
  # the poster's spelling is one no similarity measure would reach.
  test "a carried URL short-circuits the similarity measure" do
    venue = Venue.in_taxonomy.find { |v| v.domain.present? }
    skip "no placed venue with a domain" if venue.nil?

    suggestions = PlaceSuggester.for_name("Z.Z.Z.", url: "https://#{venue.domain}/programm")

    assert_equal [venue.name], suggestions.map(&:name)
  end

  test "a URL on a subdomain still resolves to its registry venue" do
    venue = Venue.in_taxonomy.find { |v| v.domain.present? }
    skip "no placed venue with a domain" if venue.nil?

    suggestions = PlaceSuggester.for_name("Z.Z.Z.", url: "https://club.#{venue.domain}/programm")

    assert_equal [venue.name], suggestions.map(&:name)
  end

  # A contributor types this field; it must degrade to name matching, not raise.
  test "an unparseable URL falls back to the similarity measure" do
    place(name: "Zorpsaal")

    assert_equal ["Zorpsaal"], PlaceSuggester.for_name("Zorpsaal", url: "not a url").map(&:name)
    assert_equal ["Zorpsaal"], PlaceSuggester.for_name("Zorpsaal", url: "zorp.example").map(&:name)
  end

  test "suggestions are ranked best first and capped" do
    place(name: "Zorpsaal")
    place(name: "Zorpsaal Nord")
    place(name: "Zorpsaal Sued")

    assert_equal "Zorpsaal", PlaceSuggester.for_name("Zorpsaal").first.name
    assert_equal 2, PlaceSuggester.for_name("Zorpsaal", limit: 2).size
  end

  # Every value is bound in one pass. Building the VALUES rows through their own
  # sanitize call and then re-sanitizing the statement made a '?' in a stored name
  # look like a bind placeholder, raising PreparedStatementInvalid.
  test "a question mark in a stored name does not break the query" do
    place(name: "Warum? Bar")

    assert_includes names_for("Warum Bar"), "Warum? Bar"
  end

  # The map the card matches typing against. Same vocabulary as the ranking, so a name
  # the suggester would offer is one the field can reach by typing it.
  test "the shipped map carries both sources with the town and canton each sits in" do
    place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    venue = Venue.in_taxonomy.first

    map = PlaceSuggester.by_name

    assert_equal ["Zorpwil", "BE"], map["Zorpsaal"]
    assert_equal [venue.locality, venue.canton], map[venue.name]
  end

  # Offering a spelling that was merged away is an invitation to re-mint it.
  test "a place merged into another is not in the shipped map" do
    canonical = place(name: "Zorpsaal")
    place(name: "Zorpsaal Halle").merge_into!(canonical)

    assert_includes PlaceSuggester.by_name.keys, "Zorpsaal"
    assert_not_includes PlaceSuggester.by_name.keys, "Zorpsaal Halle"
  end

  private

  def names_for(query) = PlaceSuggester.for_name(query).map(&:name)
end
