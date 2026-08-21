# "Save this show": per-event bookmarks + the "My saved shows" list.
class SavedEventsController < ApplicationController
  # The user's saved shows, as a day-grouped list of upcoming shows.
  def index
    @any_saved = current_user.event_saves.exists?
    # Compare the date column against a plain Date — a zoned beginning_of_day
    # timestamp slips a day across the +0200 offset (date-vs-timestamp footgun).
    @events = current_user.saved_events.includes(:locations, :genres)
                          .where("events.start_date >= ?", Date.current)
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

  # Toggle the day-of saved-show reminder. Optimistic, like #toggle: the reminder
  # Stimulus controller already flipped the checkbox and just persists the choice.
  def reminders
    current_user.update!(event_reminders: ActiveModel::Type::Boolean.new.cast(params[:enabled]))
    head :no_content
  end
end
