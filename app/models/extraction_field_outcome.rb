class ExtractionFieldOutcome < ApplicationRecord
  belongs_to :extraction_attempt

  enum :outcome, { absent: "absent", unchanged: "unchanged", supplied: "supplied",
                   corrected: "corrected", normalized: "normalized", removed: "removed",
                   discarded: "discarded" }

  FIELDS = %w[title date time place locality canton genres].freeze

  VALUED = (FIELDS - %w[title]).freeze

  PLACE_FIELDS = %w[place locality canton].freeze

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

  def self.same?(field, was, now)
    return was == now unless field == "genres"

    was.split(", ").sort == now.split(", ").sort
  end
  private_class_method :same?

  def self.normalize(field, value)
    return value.to_s.strip.presence unless field == "genres"

    value.to_s.split(",").filter_map { |genre| genre.strip.presence }.join(", ").presence
  end
  private_class_method :normalize

  def self.stored(field, value) = VALUED.include?(field) ? value : nil
  private_class_method :stored
end
