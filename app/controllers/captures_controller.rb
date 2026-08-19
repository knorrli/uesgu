# The capture funnel's one screen. `extract` runs ONE input per request because the
# client fires it once per poster (see EventCapture::Extractor for why there is no
# queue), so nothing here holds a request open for a batch.
#
# No image is ever stored, and nothing at all is persisted until a card is
# accepted — between the two the queue lives only in the DOM. Closing the tab
# therefore leaves nothing behind, which is what makes the human review a real
# checkpoint on what gets kept rather than a formality after the fact.
#
# `create` publishes ONE candidate, the one whose card is in front of the
# contributor. A refusal renders on that card, so there is no batch to keep
# survivable: no partial-success flash, no re-render of everything that did not
# publish, and no sibling-collision pre-check — two candidates off one poster
# simply read as "this event already exists" on whichever is accepted second.
class CapturesController < ApplicationController
  before_action :require_contributor
  # Every extract is a paid third-party call. Keyed by user, not IP: on Render
  # req.ip is always a Cloudflare edge address, so an IP-keyed limit is inert. The
  # 429 renders no stream, which the client already reads as a failed row.
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

  # One input per request, and the target picks the adapter — the same rule the
  # rake task follows, so there is one funnel and not a UI-shaped second one.
  def input_for(params)
    image = params[:image]
    return EventCapture::Adapters::Text.call(params[:text]) unless image.respond_to?(:read)

    # Size FIRST: the adapter's cap is a memory decision, and checking it after
    # `read` means the allocation it guards against has already happened. The
    # client-side downscale is not a control — this endpoint is reachable directly.
    return EventCapture::Adapters::Image.too_large if image.size > EventCapture::Adapters::Image::LIMIT

    EventCapture::Adapters::Image.call(image.read)
  end

  # Client-generated so each row can be replaced in place as its extraction lands.
  # Constrained because it is interpolated into a DOM id.
  def row_id
    id = params[:row_id].to_s[/\A[a-zA-Z0-9-]{1,64}\z/]
    id ? "capture-row-#{id}" : "capture-row"
  end

  # Same constraint as row_id, and same reason: the card's id addresses the region
  # this response replaces.
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
