class NotificationsController < ApplicationController
  def index
    # Read digests drop out of the inbox once opened; ?read=1 brings them back.
    @show_read = params[:read].present?
    # Preload saved_filter — the index renders each digest's filter name, an N+1
    # otherwise (see notifications/index).
    base = current_user.notifications.ordered.includes(:saved_filter)
    @notifications = (@show_read ? base : base.unread).to_a
    @read_count = current_user.notifications.read.count
    # Each digest's own size, batched into one query (see Notification.visible_event_counts).
    @event_counts = Notification.visible_event_counts(@notifications)
  end

  def show
    @notification = current_user.notifications.find(params[:id])
    @notification.mark_read!
    # Eager-load what the venue_groups/_event partials render, to avoid an N+1.
    @events = @notification.events.includes(:locations, :genres)
  end

end
