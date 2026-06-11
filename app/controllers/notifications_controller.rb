class NotificationsController < ApplicationController
  def index
    # Lazily seal any digests that have come due since the last visit.
    Notification.generate_for(current_user)
    @notifications = current_user.notifications.ordered.to_a
    @event_counts = visible_event_counts(@notifications)
  end

  def show
    @notification = current_user.notifications.find(params[:id])
    @notification.mark_read!

    @only_relevant = params[:relevant] == '1'
    events = @only_relevant ? @notification.relevant_events : @notification.events
    # Eager-load what the venue_groups/_event partials render, to avoid an N+1
    # across a digest's events.
    @events = events.includes(:locations, :styles, :genres)
  end

  private

  # Visible-event count per digest in a single query, rather than one COUNT per
  # row on the index. Digest windows are fixed at creation and non-overlapping,
  # so every event in the overall span falls into exactly one window; we bucket
  # in Ruby to keep the count tied to *current* visibility — a stored counter
  # column would drift whenever an event is later hidden by recompute_styles!.
  # Returns a Hash defaulting to 0, so digests with no visible events read 0.
  def visible_event_counts(notifications)
    counts = Hash.new(0)
    return counts if notifications.empty?

    span = notifications.map(&:period_start).min...notifications.map(&:period_end).max
    windows = notifications.sort_by(&:period_start)

    Event.visible.where(created_at: span).pluck(:created_at).each do |created_at|
      window = windows.find { |n| n.period_start <= created_at && created_at < n.period_end }
      counts[window.id] += 1 if window
    end
    counts
  end
end
