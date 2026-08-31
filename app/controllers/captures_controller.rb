class CapturesController < ApplicationController
  before_action :require_contributor
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

  def drop
    record_outcomes
    head :no_content
  end

  def genre_chips
    @genres = params[:combobox_values].to_s.split(",").filter_map { |name| name.strip.presence }.uniq
  end

  private

  def correction_for(params)
    return if params[:reread].blank?

    EventCapture::Correction.from(fields: params[:wrong], note: params[:note])
  end

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

    return EventCapture::Adapters::Image.too_large if image.size > EventCapture::Adapters::Image::LIMIT

    EventCapture::Adapters::Image.call(image.read)
  end

  def row_id
    id = params[:row_id].to_s[/\A[a-zA-Z0-9-]{1,64}\z/]
    id ? "capture-row-#{id}" : "capture-row"
  end

  def card_key = params[:card_id].to_s[/\A[a-zA-Z0-9-]{1,80}\z/] || "capture-card"

  def status_id = "#{card_key}-status"
  def form_id = "#{card_key}-form"

  def decide_card(result)
    return render_matches(result.matches) if result.error == :duplicate
    return render_status("captures/refusal", error: result.error, status: :unprocessable_entity) unless result.ok?

    record_outcomes(accepted: accepted_attributes)
    render_status("captures/published", title: result.canonical&.title || result.event.title,
                  merged: result.canonical.present?)
  end

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
