# The subscribable ICS feed of a user's saved shows + opting in/out of it.
#
# #show is public: the long random token in the URL is the only credential, the
# same model as a Google Calendar "secret address" — so a calendar app can poll
# it without a session. create/destroy manage the current user's token.
class CalendarFeedsController < ApplicationController
  allow_unauthenticated_access only: :show

  # GET /calendar/:token.ics
  def show
    user = User.find_by(calendar_feed_token: params[:token]) if params[:token].present?
    return head :not_found if user.nil?

    render plain: SavedEventsCalendar.ics(user), content_type: "text/calendar"
  end

  # POST /calendar_feed — opt in, or rotate the link to revoke the old one.
  def create
    current_user.regenerate_calendar_feed_token!
    redirect_to settings_path, notice: t("calendar_feed.created")
  end

  # DELETE /calendar_feed — remove the link (the feed 404s afterwards).
  def destroy
    current_user.clear_calendar_feed_token!
    redirect_to settings_path, notice: t("calendar_feed.removed")
  end
end
