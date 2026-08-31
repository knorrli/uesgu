require "db_test_helper"

class AliasSuggesterTest < ActiveSupport::TestCase
  test "suggests an in-use canonical within the distance bound, closest first" do
    near = Genre.create!(name: "Postpunk", events_count: 3)
    Genre.create!(name: "Polkacore", events_count: 3)
    query = Genre.create!(name: "Postpunkz")

    suggestions = AliasSuggester.call(query)

    assert_equal near.id, suggestions.first&.id
  end

  test "ignores genres that are neither in use nor placed under a parent" do
    Genre.create!(name: "Postpunk", events_count: 0)
    query = Genre.create!(name: "Postpunkz")

    assert_empty AliasSuggester.call(query)
  end
end
