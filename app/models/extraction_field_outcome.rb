# What a human did to one field of one extracted candidate, on the verify screen.
# The complement of ExtractionAttempt's `issues`, which counts values the Normalizer
# REFUSED: a confidently wrong value — an artist's origin code read as the locality —
# is well-formed, refused by nothing, and invisible there. The correction is the only
# evidence it was wrong, and it is authored by someone who saw the poster.
#
# The three shapes that matter mean opposite things, so they are never collapsed into
# "changed": `supplied` is the model abstaining (the rule is too strict), `corrected`
# is it being confidently wrong (the sourcing rule is too loose), and `removed` is it
# inventing a field the input never carried. `discarded` is the whole candidate being
# dropped, which is the worst read of all and the one a submit-only record misses.
class ExtractionFieldOutcome < ApplicationRecord
  belongs_to :extraction_attempt

  # `normalized` is a correction the prompt cannot fix: tapping a place suggestion
  # trades a faithful reading of the poster for the registry's spelling. Kept out of
  # `corrected` so the rate a prompt edit is judged on stays about misreadings.
  enum :outcome, { absent: "absent", unchanged: "unchanged", supplied: "supplied",
                   corrected: "corrected", normalized: "normalized", removed: "removed",
                   discarded: "discarded" }

  FIELDS = %w[title date time place locality canton genres].freeze

  # `title` is the free-text field a chat screenshot's sender name lands in, so its
  # outcome is recorded and its values are not. The rest are shape-constrained, and
  # the accepted half of each is published as a public event anyway.
  VALUED = (FIELDS - %w[title]).freeze

  # The tuple a place suggestion fills in one tap, and so the only fields whose change
  # can be a normalisation rather than a correction (see lib/capture/place_fields.js).
  PLACE_FIELDS = %w[place locality canton].freeze

  # The last decision on a candidate wins: a dropped card can be reopened from its
  # tile and published. The one exception is a late drop — publishing freezes the card
  # on screen, so a `discarded` write arriving after a published one is that drop's
  # fire-and-forget POST landing out of order, not a decision anybody made.
  # Serialized on the attempt row: an impatient contributor can have Accept and Reject
  # in flight on two Puma threads at once, and reading the guard outside a lock would
  # let the drop pass its check against a publish that has not committed yet — then
  # delete it. The unique index on (attempt, candidate, field) is the backstop.
  def self.record!(attempt:, candidate_index:, proposed:, accepted: nil, normalized: [])
    return if attempt.nil? || candidate_index.nil?

    attempt.with_lock do
      recorded = where(extraction_attempt_id: attempt.id, candidate_index: candidate_index)
      next if accepted.nil? && recorded.where.not(outcome: :discarded).exists?

      recorded.delete_all
      FIELDS.each do |field|
        create!(row_attributes(field, proposed, accepted, normalized)
                  .merge(extraction_attempt_id: attempt.id, candidate_index: candidate_index))
      end
    end
  end

  def self.row_attributes(field, proposed, accepted, normalized)
    was = normalize(field, proposed[field])
    now = accepted && normalize(field, accepted[field])
    outcome = outcome_for(field, was, now, dropped: accepted.nil?)
    outcome = :normalized if outcome == :corrected && normalized.include?(field)

    { field: field, outcome: outcome, proposed: stored(field, was), accepted: stored(field, now) }
  end
  private_class_method :row_attributes

  def self.outcome_for(field, was, now, dropped:)
    return :discarded if dropped
    return :absent if was.nil? && now.nil?
    return :supplied if was.nil?
    return :removed if now.nil?

    same?(field, was, now) ? :unchanged : :corrected
  end
  private_class_method :outcome_for

  # Genres are a set, not a sequence — the card renders them as chips a contributor
  # removes and re-adds, so a reordering is not a correction. Compared apart from
  # `normalize` so the stored halves stay in the order each side actually had them.
  def self.same?(field, was, now)
    return was == now unless field == "genres"

    was.split(", ").sort == now.split(", ").sort
  end
  private_class_method :same?

  # Genres arrive as one comma-separated field, so a re-spaced list must not read as a
  # correction.
  def self.normalize(field, value)
    return value.to_s.strip.presence unless field == "genres"

    value.to_s.split(",").filter_map { |genre| genre.strip.presence }.join(", ").presence
  end
  private_class_method :normalize

  def self.stored(field, value) = VALUED.include?(field) ? value : nil
  private_class_method :stored
end
