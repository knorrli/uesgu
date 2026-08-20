require "db_test_helper"

# The capture funnel's measurement row. It is written on every extraction, so the
# only behaviour of its own is the size backstop.
class ExtractionAttemptTest < ActiveSupport::TestCase
  test "prune! keeps only the most recent attempts" do
    attempts = Array.new(4) { |i| ExtractionAttempt.create!(status: :ok, created_at: Time.zone.local(2030, 1, 1, 0, i)) }

    ExtractionAttempt.prune!(keep: 2)

    assert_equal attempts.last(2).map(&:id).sort, ExtractionAttempt.pluck(:id).sort
  end

  test "an attempt with no issues stores an empty histogram, never null" do
    assert_empty ExtractionAttempt.create!(status: :ok).issues
  end
end
