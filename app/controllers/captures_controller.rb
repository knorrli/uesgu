# The capture funnel's one screen. Both actions work on ONE thing at a time —
# `extract` on one input, `create` on the one card in front of the contributor — so
# nothing here holds a request open for a batch and there is no partial-success state
# to render (see EventCapture::Extractor for why there is no queue).
#
# Nothing is persisted until a card is accepted; until then the queue lives only in
# the DOM (docs/user-event-capture-design.md).
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
    return render_status("captures/published", title: result.event.title) if result.ok?

    render_status("captures/refusal", error: result.error, status: :unprocessable_entity)
  end

  private

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
    params.permit(:title, :date, :time, :place, :locality, :canton, :url, :genres)
          .to_h.symbolize_keys
          .then { |attrs| attrs.merge(genres: attrs[:genres].to_s.split(",").map(&:strip)) }
  end
end
