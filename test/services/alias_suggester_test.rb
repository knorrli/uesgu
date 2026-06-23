require "db_test_helper"

# AliasSuggester ranks merge candidates by Levenshtein distance on the genre
# fingerprint. Synthetic taxonomy only. (The fingerprint is a stored generated
# column restricted to [a-z0-9], so it can never carry SQL; the query still binds
# it as a parameter for defense-in-depth, exercised implicitly by these tests.)
class AliasSuggesterTest < ActiveSupport::TestCase
  test "suggests an in-use canonical within the distance bound, closest first" do
    near = Genre.create!(name: "Postpunk", events_count: 3) # fingerprint "postpunk"
    Genre.create!(name: "Polkacore", events_count: 3)       # far from "postpunkz"
    query = Genre.create!(name: "Postpunkz")                # one edit from "postpunk"

    suggestions = AliasSuggester.call(query)

    assert_equal near.id, suggestions.first&.id
  end

  test "ignores genres that are neither in use nor placed under a parent" do
    Genre.create!(name: "Postpunk", events_count: 0) # not in use, no parent
    query = Genre.create!(name: "Postpunkz")

    assert_empty AliasSuggester.call(query)
  end
end
