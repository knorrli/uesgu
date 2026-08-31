# The capture funnel: `show` is where posters and pasted text are read, `manual` is the
# same event typed in by hand. Every action works on ONE thing at a time — `extract` on
# one input, `create` on the one card or page in front of the contributor — so nothing
# here holds a request open for a batch and there is no partial-success state to render
# (see EventCapture::Extractor for why there is no queue).
#
# No event is persisted until a card is accepted; until then the queue lives only in
# the DOM. What every decision does write is the measurement: one ExtractionAttempt per
# input, and one ExtractionFieldOutcome per field of every candidate a human published
# or dropped — a hand-entered event has neither, having been read by nobody.
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
    extraction = EventCapture::Extractor.call(input: input_for(params), correction: correction_for(params))

    render turbo_stream: turbo_stream.replace(
      row_id, partial: "captures/extraction",
      locals: { id: row_id, label: params[:label].to_s.truncate(80), extraction: extraction }
    )
  end

  # One publish, two screens to answer. A card is one of a queue and decides in place;
  # the hand-entry page is alone and ends in a navigation.
  def create
    result = EventCapture::Creator.call(candidate_attributes)

    respond_to do |format|
      format.turbo_stream { decide_card(result) }
      format.html { decide_page(result) }
    end
  end

  def manual
    @candidate = EventCapture::Candidate.new
  end

  # A dropped candidate is the worst read there is, and it is the one a publish-only
  # record cannot see. Answers with no content: the card is already gone on screen,
  # because dropping may not wait on — or be undone by — a metric.
  def drop
    record_outcomes
    head :no_content
  end

  # The combobox asks for its selection's chips on every change. Names, not ids: a
  # captured genre may not exist in the taxonomy at all yet.
  def genre_chips
    @genres = params[:combobox_values].to_s.split(",").filter_map { |name| name.strip.presence }.uniq
  end

  private

  # A re-read carries what a human said was wrong with the read before it, and a first
  # read carries nothing — the prompt then renders exactly as it always did. Which
  # input this is a second look at is the client's business: the poster it re-sends
  # never left the browser, so there is nothing here to match it against (see
  # app/javascript/controllers/capture_controller.js, which caps the count).
  def correction_for(params)
    return if params[:reread].blank?

    EventCapture::Correction.from(fields: params[:wrong], note: params[:note])
  end

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
  # model's reading (see lib/capture/place_fields.js).
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

  # Constrained for the same reason row_id is: both are client-generated and both are
  # interpolated into a DOM id — form_id into one the match buttons then submit by.
  def card_key = params[:card_id].to_s[/\A[a-zA-Z0-9-]{1,80}\z/] || "capture-card"

  def status_id = "#{card_key}-status"
  def form_id = "#{card_key}-form"

  # Every outcome replaces the card's status slot; the queue behind it carries on.
  def decide_card(result)
    return render_matches(result.matches) if result.error == :duplicate
    return render_status("captures/refusal", error: result.error, status: :unprocessable_entity) unless result.ok?

    record_outcomes(accepted: accepted_attributes)
    render_status("captures/published", title: result.canonical&.title || result.event.title,
                  merged: result.canonical.present?)
  end

  # Records no ExtractionFieldOutcome, and correctly so: with no attempt token there is
  # no proposal to compare against, and a hand-entered event is not a read anyone can be
  # judged on. A question comes back as the page again with what was typed still in it,
  # since there is no status slot to answer into and nothing left on screen otherwise.
  def decide_page(result)
    return redraw_manual(matches: result.matches) if result.error == :duplicate
    return redraw_manual(error: result.error) unless result.ok?

    redirect_to capture_path, notice: published_notice(result)
  end

  def redraw_manual(matches: nil, error: nil)
    @candidate = submitted_candidate
    @matches = matches && helpers.capture_matches(matches, candidate_attributes)
    @error = error
    render :manual, status: :unprocessable_entity
  end

  def published_notice(result)
    return t("capture.card.merged", title: result.canonical.title) if result.canonical

    t("capture.card.published", title: result.event.title)
  end

  # What was typed, back in the shape the fields render from. Only ever used to redraw a
  # page that was refused, so a date the form could not have produced is simply dropped
  # rather than defended against.
  def submitted_candidate
    attrs = candidate_attributes
    EventCapture::Candidate.new(
      title: attrs[:title], subtitle: attrs[:description], date: parsed_date(attrs[:date]),
      time: attrs[:time], place: attrs[:place], locality: attrs[:locality],
      canton: attrs[:canton], genres: attrs[:genres]
    )
  end

  def parsed_date(value)
    Date.parse(value.to_s)
  rescue Date::Error
    nil
  end

  # 422 so Turbo leaves the card open and capture#decided does not settle it: nothing
  # was published, and the card is being asked a question rather than told it failed.
  def render_matches(matches)
    render_status("captures/matches", status: :unprocessable_entity, form_id: form_id,
                  matches: helpers.capture_matches(matches, candidate_attributes))
  end

  def candidate_attributes
    params.permit(:title, :description, :date, :time, :place, :locality, :canton, :genres,
                  :matched_event_id, :acknowledged)
          .to_h.symbolize_keys
          .then { |attrs| attrs.merge(genres: attrs[:genres].to_s.split(",").map(&:strip)) }
  end
end
