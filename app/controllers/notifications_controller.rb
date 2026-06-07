class NotificationsController < ApplicationController
  def index
    # Lazily seal any digests that have come due since the last visit.
    Notification.generate_for(current_user)
    @notifications = current_user.notifications.ordered
  end

  def show
    @notification = current_user.notifications.find(params[:id])
    @notification.mark_read!

    @only_relevant = params[:relevant] == "1"
    @events = @only_relevant ? @notification.relevant_events : @notification.events
  end
end
