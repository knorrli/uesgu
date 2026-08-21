# The capture funnel's one screen. Both actions work on ONE thing at a time —
# `extract` on one input, `create` on the one card in front of the contributor — so
# nothing here holds a request open for a batch and there is no partial-success state
# to render (see EventCapture::Extractor for why there is no queue).
#
# No event is persisted until a card is accepted; until then the queue lives only in
# the DOM. What every decision does write is the
# measurement: one ExtractionAttempt per input, and one ExtractionFieldOutcome per
# field of every candidate a human published or dropped.
class CapturesController < ApplicationController
  before_action :require_contributor
  # Every extract is a paid third-party call. Keyed by user, not IP: on Render req.ip
  # is always a Cloudflare edge address, so an IP-keyed limit is inert. The 429
  # deliberately renders no stream — the client already reads that as a failed row.
  rate_limit to: 60, within: 1.minute, only: :extract,
             by: -> { current_user&.id }, with: -> { head :too_many_requests }

  def show
  end

  def extract
    extraction = EventCapture::Extractor.call(input: input_for(params))

    render turbo_stream: turbo_stream.replace(
      row_id, partial: "captures/extraction",
      locals: { id: row_id, label: params[:label].to_s.truncate(80), extraction: extraction }
    )
  end

  def create
    result = EventCapture::Creator.call(candidate_attributes)
    return render_status("captures/refusal", error: result.error, status: :unprocessable_entity) unless result.ok?

    record_outcomes(accepted: accepted_attributes)
    render_status("captures/published", title: result.event.title)
  end

  # Records no ExtractionFieldOutcome, and correctly so: with no attempt token there
  # is no proposal to compare against, and a hand-entered event is not a read anyone
  # can be judged on.
  def blank
    render turbo_stream: turbo_stream.replace(
      row_id, partial: "captures/manual",
      locals: { id: row_id, candidate: EventCapture::Candidate.new }
    )
  end

  # A dropped candidate is the worst read there is, and it is the one a publish-only
  # record cannot see. Answers with no content: the card is already gone on screen,
  # because dropping may not wait on — or be undone by — a metric.
  def drop
    record_outcomes
    head :no_content
  end

  # Type-ahead over the genres already in use, so a contributor lands on the existing
  # spelling instead of minting a fourth one. Dispositioned genres are left out: a
  # genre we ignore, hide or block is not something to suggest, and an alias would
  # tag the raw token rather than its canonical.
  SUGGESTION_LIMIT = 20

  def genre_options
    @genres = Genre.in_use.where(ignored_at: nil, hidden_at: nil, blocked_at: nil, canonical_id: nil)
                   .where("name ILIKE ?", "%#{params[:q]}%")
                   .by_usage.limit(SUGGESTION_LIMIT)
  end

  # The combobox asks for its selection's chips on every change. Names, not ids: a
  # captured genre may not exist in the taxonomy at all yet.
  def genre_chips
    @genres = params[:combobox_values].to_s.split(",").filter_map { |name| name.strip.presence }.uniq
  end

  private

  # Measuring the funnel may not break it, so an expired or forged token costs the row
  # and nothing else. Values ride in from the card (see captures/_candidate).
  def record_outcomes(accepted: nil)
    ExtractionFieldOutcome.record!(
      attempt: ExtractionAttempt.find_by_capture_token(params[:attempt_token]),
      candidate_index: candidate_index, proposed: proposed_attributes,
      accepted: accepted, normalized: normalized_fields
    )
  rescue StandardError => e
    Rails.logger.error("ExtractionFieldOutcome.record! failed: #{e.class}: #{e.message}")
  end

  def candidate_index = params[:candidate_index].to_s[/\A\d+\z/]&.to_i

  def proposed_attributes
    ExtractionFieldOutcome::FIELDS.index_with { |field| params[:"proposed_#{field}"] }
  end

  def accepted_attributes
    ExtractionFieldOutcome::FIELDS.index_with { |field| params[field.to_sym] }
  end

  # Fields the contributor filled from a place suggestion rather than by judging the
  # model's reading (see capture_controller.js).
  def normalized_fields
    ExtractionFieldOutcome::PLACE_FIELDS.select { |field| params[:"normalized_#{field}"].present? }
  end

  def render_status(partial, status: :ok, **locals)
    render turbo_stream: turbo_stream.replace(status_id, partial: partial,
                                              locals: locals.merge(id: status_id)),
           status: status
  end

  def input_for(params)
    image = params[:image]
    return EventCapture::Adapters::Text.call(params[:text]) unless image.respond_to?(:read)

    # Size FIRST: the cap is a memory decision, so checking it after `read` means the
    # allocation it guards against has already happened. The client-side downscale is
    # not a control — this endpoint is reachable directly.
    return EventCapture::Adapters::Image.too_large if image.size > EventCapture::Adapters::Image::LIMIT

    EventCapture::Adapters::Image.call(image.read)
  end

  # Client-generated, and constrained because it is interpolated into a DOM id.
  def row_id
    id = params[:row_id].to_s[/\A[a-zA-Z0-9-]{1,64}\z/]
    id ? "capture-row-#{id}" : "capture-row"
  end

  def status_id
    id = params[:card_id].to_s[/\A[a-zA-Z0-9-]{1,80}\z/]
    "#{id || 'capture-card'}-status"
  end

  def candidate_attributes
    params.permit(:title, :description, :date, :time, :place, :locality, :canton, :url, :genres)
          .to_h.symbolize_keys
          .then { |attrs| attrs.merge(genres: attrs[:genres].to_s.split(",").map(&:strip)) }
  end
end
