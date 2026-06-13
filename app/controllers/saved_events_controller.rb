# "Save this show": per-event bookmarks + the "My saved shows" list.
class SavedEventsController < ApplicationController
  # The user's upcoming saved shows, grouped by day in the view.
  def index
    @events = current_user.saved_events
                          .where("events.start_date >= ?", Date.current.beginning_of_day)
                          .includes(:locations, :styles, :genres)
                          .order(:start_date, :start_time, :title)
  end

  # Toggle a single event's saved state. Optimistic — the save Stimulus
  # controller already flipped the bookmark, so we just persist and answer empty.
  def toggle
    event = Event.find(params[:event_id])
    existing = current_user.event_saves.find_by(event_id: event.id)
    existing ? existing.destroy : current_user.event_saves.create(event: event)
    head :no_content
  end
end
