class GenresController < ApplicationController
  before_action :require_admin

  STATUS_SCOPES = {
    'unassigned' => :unassigned,
    'assigned' => :assigned,
    'ignored' => :ignored,
    'hidden' => :hidden,
    'blocked' => :blocked
  }.freeze

  # Browse default is alphabetical (finding a known genre); 'count' surfaces the
  # heaviest hitters (the queue's order).
  SORT_SCOPES = { 'name' => :by_name, 'count' => :by_usage }.freeze

  # Standard CRUD entry, filterable by status and sortable. Browsing shows the
  # curation catalogue (`Genre.listable` = in use + parked); a name search instead
  # reaches *every* genre — including dormant taxonomy entries and genres you've
  # touched that currently tag 0 events — so nothing is ever truly hidden, it's
  # just one search away.
  def index
    @status = STATUS_SCOPES.key?(params[:status]) ? params[:status] : 'all'
    @sort = SORT_SCOPES.key?(params[:sort]) ? params[:sort] : 'name'
    scope = @status == 'all' ? Genre.all : Genre.public_send(STATUS_SCOPES[@status])
    scope = params[:q].present? ? scope.where('name ILIKE ?', "%#{params[:q]}%") : scope.listable
    @genres = scope.public_send(SORT_SCOPES[@sort]).includes(:styles).page(params[:page]).per(50)
  end

  # The assignment queue: serve the single highest-impact unmapped genre, plus
  # style suggestions and the events it appears on. Assigning/ignoring it
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

  def ignore
    Genre.find(params[:id]).ignore!
    redirect_to return_to
  end

  def hide
    Genre.find(params[:id]).hide!
    redirect_to return_to
  end

  def block
    Genre.find(params[:id]).block!
    redirect_to return_to
  end

  def restore
    Genre.find(params[:id]).restore!
    redirect_to return_to
  end

  # Fold this genre into a canonical one (a semantic alias the fingerprint can't
  # catch). The combobox emits a single genre id.
  def merge
    canonical = Genre.find(genre_params[:canonical_genre_id])
    Genre.find(params[:id]).merge_into!(canonical)
    redirect_to return_to
  end

  private

  def genre_params
    params.expect(genre: %i[style_ids canonical_genre_id])
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
