class GenresController < ApplicationController
  before_action :require_admin

  STATUS_SCOPES = {
    'unassigned' => :unassigned,
    'assigned' => :assigned,
    'dismissed' => :dismissed,
    'excluded' => :excluded
  }.freeze

  # Browsable, searchable list of every genre in use — standard CRUD entry,
  # filterable by assignment status (this is also where dismissed genres live).
  def index
    @status = STATUS_SCOPES.key?(params[:status]) ? params[:status] : 'all'
    scope = @status == 'all' ? Genre.in_use : Genre.in_use.public_send(STATUS_SCOPES[@status])
    scope = scope.where('name ILIKE ?', "%#{params[:q]}%") if params[:q].present?
    @genres = scope.by_usage.includes(:styles).page(params[:page]).per(50)
  end

  # The assignment queue: serve the single highest-impact unmapped genre, plus
  # style suggestions and the events it appears on. Assigning/dismissing it
  # returns here, surfacing the next one — a "tinder" flow.
  def queue
    @remaining = Genre.unassigned.count
    @genre = Genre.unassigned.by_usage.first
    @suggestions = @genre ? StyleSuggester.call(@genre) : []
    @sample_events = sample_events_for(@genre)
  end

  def edit
    @genre = Genre.find(params[:id])
    @suggestions = StyleSuggester.call(@genre)
    @sample_events = sample_events_for(@genre)
  end

  def update
    Genre.find(params[:id]).assign_styles!(genre_params[:style_ids])
    redirect_to return_to
  end

  def dismiss
    Genre.find(params[:id]).dismiss!
    redirect_to return_to
  end

  def exclude
    Genre.find(params[:id]).exclude!
    redirect_to return_to
  end

  def restore
    Genre.find(params[:id]).restore!
    redirect_to return_to
  end

  private

  def genre_params
    params.expect(genre: [:style_ids])
  end

  # Where to land after an action. Constrained to internal paths so the
  # round-tripped value can't be turned into an open redirect.
  def return_to
    to = params[:return_to].to_s
    to.start_with?('/') ? to : genres_path
  end

  def sample_events_for(genre)
    return Event.none unless genre

    Event.tagged_with(genre.name, on: :genres).includes(:locations).order(start_date: :desc).limit(5)
  end
end
