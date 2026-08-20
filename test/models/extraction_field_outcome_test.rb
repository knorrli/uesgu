require "db_test_helper"

# The diff between what the model proposed and what a human published. Every case
# here is one of the three shapes the leaderboard is built on, plus the drop.
class ExtractionFieldOutcomeTest < ActiveSupport::TestCase
  def attempt = @attempt ||= ExtractionAttempt.create!(status: :ok, medium: "image")

  def proposed(**overrides)
    { "title" => "Zorpcore Nacht", "date" => "2026-09-01", "time" => "20:00", "place" => "Zorpsaal",
      "locality" => "Zorpwil", "canton" => "BE", "genres" => "Zorpwave" }.merge(overrides.stringify_keys)
  end

  def record(proposed:, accepted: nil, index: 0, normalized: [])
    ExtractionFieldOutcome.record!(attempt: attempt, candidate_index: index, proposed: proposed,
                                   accepted: accepted, normalized: normalized)
  end

  def outcome_for(field) = ExtractionFieldOutcome.find_by(field: field)

  test "an untouched publish records every field as unchanged" do
    record(proposed: proposed, accepted: proposed)

    assert_equal ExtractionFieldOutcome::FIELDS.sort, ExtractionFieldOutcome.pluck(:field).sort
    assert ExtractionFieldOutcome.all.all?(&:unchanged?)
  end

  # The three shapes mean opposite things about the prompt, so they are never one
  # "changed" bucket.
  test "the three shapes are told apart, and keep both values" do
    record(proposed: proposed(time: nil, locality: "Us", place: "Zorpsaal"),
           accepted: proposed(time: "21:00", locality: "Zorpwil", place: nil))

    assert_predicate outcome_for("time"), :supplied?
    assert_predicate outcome_for("locality"), :corrected?
    assert_predicate outcome_for("place"), :removed?

    assert_equal "Us", outcome_for("locality").proposed
    assert_equal "Zorpwil", outcome_for("locality").accepted
  end

  test "a field neither side filled is absent, not a correction" do
    record(proposed: proposed(time: nil), accepted: proposed(time: ""))

    assert_predicate outcome_for("time"), :absent?
  end

  test "re-spacing a genre list is not a correction" do
    record(proposed: proposed(genres: "Zorpwave,Flarncore"), accepted: proposed(genres: " Zorpwave , Flarncore "))

    assert_predicate outcome_for("genres"), :unchanged?
  end

  # The free-text field a chat screenshot's sender name lands in: the outcome is the
  # signal, the value is not worth keeping.
  test "the title's outcome is recorded without either value" do
    record(proposed: proposed(title: "Zorp Zorpsson"), accepted: proposed(title: "Zorpcore Nacht"))

    title = outcome_for("title")
    assert_predicate title, :corrected?
    assert_nil title.proposed
    assert_nil title.accepted
  end

  test "a dropped candidate records what it had proposed, and no accepted value" do
    record(proposed: proposed)

    assert ExtractionFieldOutcome.all.all?(&:discarded?)
    assert_equal "Zorpsaal", outcome_for("place").proposed
    assert_nil outcome_for("place").accepted
  end

  # A drop is reversible on screen: the card can be reopened from its strip and
  # published, and that later decision is the one that happened.
  test "publishing after a drop replaces the discarded rows" do
    record(proposed: proposed)
    record(proposed: proposed, accepted: proposed)

    assert_equal ExtractionFieldOutcome::FIELDS.size, ExtractionFieldOutcome.count
    assert_empty ExtractionFieldOutcome.discarded
  end

  test "candidates off one input are recorded apart" do
    record(proposed: proposed, index: 0)
    record(proposed: proposed, accepted: proposed, index: 1)

    assert_equal ExtractionFieldOutcome::FIELDS.size, ExtractionFieldOutcome.where(candidate_index: 0).count
    assert_empty ExtractionFieldOutcome.where(candidate_index: 1).discarded
  end

  test "an unresolved attempt records nothing rather than raising" do
    assert_no_difference -> { ExtractionFieldOutcome.count } do
      ExtractionFieldOutcome.record!(attempt: nil, candidate_index: 0, proposed: proposed)
    end
  end

  # The drop is posted fire-and-forget, so it can land after the publish that
  # superseded it — and publishing freezes the card, so nothing legitimately follows.
  test "a late drop does not overwrite the publish that superseded it" do
    record(proposed: proposed, accepted: proposed)
    record(proposed: proposed)

    assert_empty ExtractionFieldOutcome.discarded
    assert_equal ExtractionFieldOutcome::FIELDS.size, ExtractionFieldOutcome.unchanged.count
  end

  # Tapping a suggestion trades the poster's spelling for the registry's, which is not
  # something a prompt edit could have got right.
  test "a value taken from a place suggestion is normalized, not corrected" do
    record(proposed: proposed(place: "Zorpsaal Zorpwil"), accepted: proposed(place: "Zorpsaal"),
           normalized: %w[place])

    assert_predicate outcome_for("place"), :normalized?
  end

  test "a flag on a field nobody changed leaves the outcome alone" do
    record(proposed: proposed, accepted: proposed, normalized: %w[place])

    assert_predicate outcome_for("place"), :unchanged?
  end

  test "pruning an attempt takes its outcomes with it" do
    record(proposed: proposed)
    ExtractionAttempt.create!(status: :ok, created_at: 1.minute.from_now)

    ExtractionAttempt.prune!(keep: 1)

    assert_empty ExtractionFieldOutcome.all
  end
end
