class NotificationsController < ApplicationController
  def index
    # Lazily seal any digests that have come due since the last visit.
    Notification.generate_for(current_user)
    @notifications = current_user.notifications.ordered
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
end
