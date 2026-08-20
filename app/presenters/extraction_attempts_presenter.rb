# Backs /admin/extraction_attempts: how the capture funnel's model calls are
# actually going, over the most recent window of ExtractionAttempt rows.
#
# Two questions, deliberately kept apart. Is the provider erroring — the failure
# codes. And is the prompt getting worse at a field — the `issues` codes the
# Normalizer wrote, grouped by model and prompt sha so a wording edit can be read
# as a before/after instead of argued about.
#
# The window is loaded once and pivoted in memory (as ScrapeRunsPresenter does):
# it is bounded, and every number here is a sum over the same rows the table
# below lists, so the page cannot show a stat the list contradicts.
class ExtractionAttemptsPresenter
  WINDOW = 100

  # One field's report card. `discarded` rows carry no human value, so they are the
  # denominator of nothing — every rate here is taken over the decisions where a human
  # actually published something.
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

  # {"provider_error" => 3}, commonest first.
  def failures_by_code
    tally(attempts.select(&:failed?).map { |attempt| attempt.code || "unknown" })
  end

  # {"time_unparseable" => 7}, commonest first — summed across every candidate in
  # the window, so a value above `candidates` just means one candidate tripped
  # several rules.
  def issue_counts
    attempts.each_with_object(Hash.new(0)) { |attempt, counts|
      attempt.issues.each { |code, count| counts[code] += count }
    }.sort_by { |_code, count| -count }.to_h
  end

  # Newest group first: `attempts` is already recent-first and group_by keeps
  # insertion order, so the prompt in force right now leads the table.
  def groups
    attempts.reject { |attempt| attempt.prompt_sha.nil? }
            .group_by { |attempt| [attempt.model, attempt.prompt_sha] }
            .map { |(model, sha), rows| Group.new(model: model, prompt_sha: sha, attempts: rows) }
  end

  # Per field, what the human did to the model's value on the verify screen. Fields
  # nobody has decided on yet are left out rather than shown as a row of zeros.
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
