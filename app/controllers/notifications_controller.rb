class NotificationsController < ApplicationController
  def index
    # Read digests drop out of the inbox once opened; ?read=1 brings them back.
    @show_read = params[:read].present?
    base = current_user.notifications.ordered
    @notifications = (@show_read ? base : base.unread).to_a
    @read_count = current_user.notifications.read.count
    # Each digest's own size: rule-based notifications count their event_ids
    # snapshot, legacy ones their created_at window (see Notification#events).
    @event_counts = @notifications.to_h { |n| [n.id, n.events.count] }
  end

  def show
    @notification = current_user.notifications.find(params[:id])
    @notification.mark_read!
    # Eager-load what the venue_groups/_event partials render, to avoid an N+1.
    @events = @notification.events.includes(:locations, :genres)
  end

end
