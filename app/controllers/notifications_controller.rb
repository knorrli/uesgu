class NotificationsController < ApplicationController
  def index
    @show_read = params[:read].present?
    base = current_user.notifications.ordered.includes(:saved_filter)
    @notifications = (@show_read ? base.read : base.unread).to_a
    @read_count = current_user.notifications.read.count
    @unread_count = current_user.notifications.unread.count
    @event_counts = Notification.visible_event_counts(@notifications)
  end

  def mark_all_read
    now = Time.current
    current_user.notifications.unread.update_all(read_at: now, updated_at: now)
    redirect_to notifications_path, notice: t("notifications.index.all_marked_read")
  end

  def show
    @notification = current_user.notifications.find(params[:id])
    @notification.mark_read!
    @events = @notification.events.includes(:locations, :genres)
  end
end
