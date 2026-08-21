class NotificationsController < ApplicationController
  def index
    # Two flat-text tabs — Ungelesen | Gelesen: each is a distinct slice (unread vs
    # read), not an append. Default is unread; ?read=1 is the read archive.
    @show_read = params[:read].present?
    # Preload saved_filter — the index renders each digest's filter name, an N+1
    # otherwise (see notifications/index).
    base = current_user.notifications.ordered.includes(:saved_filter)
    @notifications = (@show_read ? base.read : base.unread).to_a
    @read_count = current_user.notifications.read.count
    @unread_count = current_user.notifications.unread.count
    # Each digest's own size, batched into one query (see Notification.visible_event_counts).
    @event_counts = Notification.visible_event_counts(@notifications)
  end

  # Mark every unread digest read in one UPDATE. update_all (not each(&:mark_read!))
  # because Notification has no callbacks or validations worth running here and an
  # inbox can hold a lot of rows; updated_at is set by hand since update_all skips
  # the timestamp. Scoped through current_user, so it can only ever clear your own.
  def mark_all_read
    now = Time.current
    current_user.notifications.unread.update_all(read_at: now, updated_at: now)
    # Back to the unread tab — now the "Alles gelesen" empty state, which also
    # re-renders the nav without its unread dot/badge.
    redirect_to notifications_path, notice: t("notifications.index.all_marked_read")
  end

  def show
    @notification = current_user.notifications.find(params[:id])
    @notification.mark_read!
    # Eager-load what the venue_groups/_event partials render, to avoid an N+1.
    @events = @notification.events.includes(:locations, :genres)
  end
end
