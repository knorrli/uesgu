class SavedEventsController < ApplicationController
  def index
    @any_saved = current_user.event_saves.exists?
    @events = current_user.saved_events.includes(:locations, :genres)
                          .where("events.start_date >= ?", Date.current)
                          .order(:start_date, :start_time, :title)
  end

  def toggle
    event = Event.find(params[:event_id])
    existing = current_user.event_saves.find_by(event_id: event.id)
    existing ? existing.destroy : current_user.event_saves.create(event: event)
    head :no_content
  end

  def reminders
    current_user.update!(event_reminders: ActiveModel::Type::Boolean.new.cast(params[:enabled]))
    head :no_content
  end
end
