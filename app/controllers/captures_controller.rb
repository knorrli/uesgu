# The capture funnel's one screen: a contributor turns a poster photo or pasted
# text into events we don't scrape, which is the only way the long tail — house
# shows, one-offs, tiny rooms — ever reaches the feed.
#
# The flow is three requests, not one. `show` renders the picker; the client fires
# `extract` ONCE PER INPUT (8 x 2.3s does not fit in one request, and there is no
# queue to reach for — the queue adapter is :inline and Solid Queue was removed for
# competing with Puma for RAM), each answering with the candidates for that input
# alone; `create` publishes the ones a human accepted.
#
# NOTHING is persisted before `create`, images least of all (decision 9). Between
# extract and create the batch lives in the DOM, which is what makes "the verify
# screen is the PII checkpoint" literally true: a contributor who closes the tab
# leaves nothing behind. See docs/user-event-capture-design.md.
class CapturesController < ApplicationController
  before_action :require_contributor

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
    @results = accepted_candidates.map { |attrs| EventCapture::Creator.call(attrs) }
    published = @results.select(&:ok?)

    if published.any?
      redirect_to root_path, notice: t("capture.published", count: published.size)
    else
      redirect_to capture_path, alert: t("capture.none_published")
    end
  end

  private

  # One input per request, and the target picks the adapter — the same rule the
  # rake task follows, so there is one funnel and not a UI-shaped second one.
  def input_for(params)
    return EventCapture::Adapters::Image.call(params[:image].read) if params[:image].respond_to?(:read)

    EventCapture::Adapters::Text.call(params[:text])
  end

  # Client-generated, so a row can be replaced in place as its extraction lands and
  # a failed input is one row to retry rather than a dead batch. Constrained
  # because it is interpolated into a DOM id.
  def row_id
    id = params[:row_id].to_s[/\A[a-zA-Z0-9-]{1,64}\z/]
    id ? "capture-row-#{id}" : "capture-row"
  end

  def accepted_candidates
    params.fetch(:candidates, {}).values.filter_map do |candidate|
      next unless ActiveModel::Type::Boolean.new.cast(candidate[:accept])

      candidate.permit(:title, :date, :time, :place, :locality, :canton, :url, :genres)
               .to_h.symbolize_keys
               .then { |attrs| attrs.merge(genres: attrs[:genres].to_s.split(",")) }
    end
  end
end
