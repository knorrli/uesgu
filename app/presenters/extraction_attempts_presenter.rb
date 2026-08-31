class ExtractionAttemptsPresenter
  WINDOW = 100

  FieldRow = Data.define(:field, :counts) do
    def total = counts.values.sum
    def count(outcome) = counts.fetch(outcome, 0)
    def published = total - count("discarded")

    def rate(outcome)
      return 0 if published.zero?

      (100.0 * count(outcome) / published).round
    end
  end

  Group = Data.define(:model, :prompt_sha, :attempts) do
    def count = attempts.size
    def failed = attempts.count(&:failed?)
    def candidates = attempts.sum(&:candidates_count)
    def issues = attempts.sum { |attempt| attempt.issues.values.sum }
  end

  def initialize(prompt_sha: nil, window: WINDOW)
    @prompt_sha = prompt_sha.presence
    @attempts = ExtractionAttempt.recent.then { |scope| @prompt_sha ? scope.where(prompt_sha: @prompt_sha) : scope }
                                 .limit(window).to_a
  end

  attr_reader :attempts, :prompt_sha

  def any? = attempts.any?
  def total = attempts.size
  def failed = attempts.count(&:failed?)
  def candidates = attempts.sum(&:candidates_count)
  def tokens = attempts.sum { |attempt| attempt.input_tokens + attempt.output_tokens }

  def average_duration_ms
    durations = attempts.filter_map(&:duration_ms)
    return if durations.empty?

    durations.sum / durations.size
  end

  def failures_by_code
    tally(attempts.select(&:failed?).map { |attempt| attempt.code || "unknown" })
  end

  def issue_counts
    attempts.each_with_object(Hash.new(0)) { |attempt, counts|
      attempt.issues.each { |code, count| counts[code] += count }
    }.sort_by { |_code, count| -count }.to_h
  end

  def groups
    attempts.reject { |attempt| attempt.prompt_sha.nil? }
            .group_by { |attempt| [attempt.model, attempt.prompt_sha] }
            .map { |(model, sha), rows| Group.new(model: model, prompt_sha: sha, attempts: rows) }
  end

  def field_rows
    @field_rows ||= begin
      counts = ExtractionFieldOutcome.where(extraction_attempt_id: attempts.map(&:id))
                                     .group(:field, :outcome).count
      ExtractionFieldOutcome::FIELDS.filter_map do |field|
        by_outcome = counts.filter_map { |(f, outcome), count| [outcome, count] if f == field }.to_h
        FieldRow.new(field: field, counts: by_outcome) if by_outcome.any?
      end
    end
  end

  def percent(part, whole)
    return 0 if whole.to_i.zero?

    (100.0 * part / whole).round
  end

  private

  def tally(values)
    values.tally.sort_by { |_value, count| -count }.to_h
  end
end
