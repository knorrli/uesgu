# "Save this show": per-event bookmarks + the "My saved shows" list.
class SavedEventsController < ApplicationController
  include ListingViewMode

  # The user's saved shows, as a day-grouped list (upcoming only) or a month
  # calendar — the same list/calendar toggle as the main programme.
  def index
    @any_saved = current_user.event_saves.exists?
    @view = resolve_view(session_key: :saved_events_view, account_attr: :saved_events_view)
    # The venue/style tags are follow-toggles here too, same as the main programme,
    # so clicking a name follows/unfollows it (consistent everywhere) rather than
    # behaving differently on this one page.
    @calendar_interactive = true

    scope = current_user.saved_events.includes(:locations, :genres)
    if @view == 'calendar'
      @calendar_start = (Date.parse(params[:start_date]) rescue nil) || Date.current
      # The focused month plus a week of padding so adjacent-month grid cells are
      # covered (mirrors EventsController#index).
      @events = scope.where(start_date: (@calendar_start.beginning_of_month - 7)..(@calendar_start.end_of_month + 7))
                     .order(:start_date, :start_time, :title)
      @open_day = (Date.parse(params[:day]) rescue nil) if params[:day].present?
      # The month is already loaded, so slice the open day out of it rather than
      # re-querying.
      @open_day_events = @events.select { |event| event.start_date == @open_day } if @open_day
    else
      # Compare the date column against a plain Date — a zoned beginning_of_day
      # timestamp slips a day across the +0200 offset (date-vs-timestamp footgun).
      @events = scope.where('events.start_date >= ?', Date.current)
                     .order(:start_date, :start_time, :title)
    end
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
