class CalendarFeedsController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    user = User.find_by(calendar_feed_token: params[:token]) if params[:token].present?
    return head :not_found if user.nil?

    render plain: SavedEventsCalendar.ics(user), content_type: "text/calendar"
  end

  def create
    current_user.regenerate_calendar_feed_token!
    redirect_to settings_path, notice: t("calendar_feed.created")
  end

  def destroy
    current_user.clear_calendar_feed_token!
    redirect_to settings_path, notice: t("calendar_feed.removed")
  end
end
