# The capture funnel's one screen. `extract` runs ONE input per request because the
# client fires it once per poster (see EventCapture::Extractor for why there is no
# queue), so nothing here holds a request open for a batch.
#
# No image is ever stored, and nothing at all is persisted before `create` —
# between the two the batch lives only in the DOM. Closing the tab therefore leaves
# nothing behind, which is what makes the human review a real checkpoint on what
# gets kept rather than a formality after the fact.
class CapturesController < ApplicationController
  before_action :require_contributor
  # Every extract is a paid third-party call. Keyed by user, not IP: on Render
  # req.ip is always a Cloudflare edge address, so an IP-keyed limit is inert. The
  # 429 renders no stream, which the client already reads as a failed row.
  rate_limit to: 60, within: 1.minute, only: :extract,
             by: -> { current_user&.id }, with: -> { head :too_many_requests }

  def show
    @retries ||= []
  end

  def extract
    extraction = EventCapture::Extractor.call(input: input_for(params))

    render turbo_stream: turbo_stream.replace(
      row_id, partial: "captures/extraction",
      locals: { id: row_id, label: params[:label].to_s.truncate(80), extraction: extraction }
    )
  end

  # Refused candidates are re-rendered rather than redirected away: nothing is
  # persisted before this point, so a redirect would throw away every extraction
  # that did not publish, including the ones needing one field corrected.
  def create
    results = publish_each(accepted_candidates)
    published = results.count { |_, result| result.ok? }
    @retries = results.reject { |_, result| result.ok? }
                      .map { |attrs, result| [candidate_from(attrs), result.error] }

    return redirect_to root_path, notice: t("capture.published", count: published) if @retries.empty?

    flash.now[:alert] = t("capture.partly_published", count: published, failed: @retries.size)
    render :show, status: :unprocessable_entity
  end

  private

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

  def candidate_from(attrs)
    EventCapture::Candidate.new(
      title: attrs[:title], date: parsed_date(attrs[:date]), time: attrs[:time],
      place: attrs[:place], locality: attrs[:locality], canton: attrs[:canton],
      source_url: attrs[:url], genres: attrs[:genres]
    )
  end

  def parsed_date(value)
    Date.strptime(value.to_s, "%Y-%m-%d")
  rescue Date::Error
    nil
  end

  # Two candidates off one poster carry the same source_url, so the second would
  # hit the unique index and be reported as "the scraper already has this" — true of
  # the index, misleading about the cause, and unfixable without knowing the clash
  # is with its own sibling.
  def publish_each(candidates)
    seen = Set.new
    candidates.map do |attrs|
      next [attrs, EventCapture::Creator::Result.new(error: :duplicate_in_batch)] if
        attrs[:url].present? && !seen.add?(attrs[:url])

      [attrs, EventCapture::Creator.call(attrs)]
    end
  end

  def accepted_candidates
    submitted = params[:candidates]
    return [] unless submitted.respond_to?(:values)

    submitted.values.filter_map do |candidate|
      next unless candidate.respond_to?(:permit)
      next unless ActiveModel::Type::Boolean.new.cast(candidate[:accept])

      candidate.permit(:title, :date, :time, :place, :locality, :canton, :url, :genres)
               .to_h.symbolize_keys
               .then { |attrs| attrs.merge(genres: attrs[:genres].to_s.split(",").map(&:strip)) }
    end
  end
end
