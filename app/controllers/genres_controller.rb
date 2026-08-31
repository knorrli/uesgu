class GenresController < ApplicationController
  include CatalogueBrowsing

  before_action :require_admin

  STATUS_SCOPES = {
    "unplaced" => :unplaced,
    "placed" => :placed,
    "ignored" => :ignored,
    "hidden" => :hidden,
    "blocked" => :blocked
  }.freeze

  SORT_SCOPES = { "name" => :by_name, "count" => :by_usage }.freeze

  def index
    @status = catalogue_param(:status, STATUS_SCOPES, default: "all")
    @sort = catalogue_param(:sort, SORT_SCOPES, default: "name")
    scope = @status == "all" ? Genre.all : Genre.public_send(STATUS_SCOPES[@status])
    scope = params[:q].present? ? scope.where("name ILIKE ?", "%#{params[:q]}%") : scope.listable
    @genres = scope.public_send(SORT_SCOPES[@sort]).includes(:parent).page(params[:page]).per(PAGE_SIZE)
  end

  def tree
    genres = Genre.where(hidden_at: nil, blocked_at: nil, ignored_at: nil, canonical_id: nil)
                  .by_name.to_a
    @children = genres.group_by(&:parent_id)
    parents = @children.keys.compact.to_set
    @roots = (@children[nil] || []).select { |g| parents.include?(g.id) }
    @placed = Genre.placed.count
    @unplaced = Genre.unplaced.count
  end

  def queue
    @remaining = Genre.unplaced.count
    @genre = Genre.unplaced.by_usage.first
    load_suggestions
    @sample_events = sample_events_for(@genre)
  end

  def edit
    @genre = Genre.find(params[:id])
    load_suggestions
    @sample_events = sample_events_for(@genre)
  end

  def set_parent
    Genre.find(params[:id]).set_parent!(genre_params[:parent_genre_id])
    redirect_to return_to
  rescue ArgumentError => e
    redirect_to return_to, alert: e.message
  end

  def chips
    @genres = params[:combobox_values].to_s.split(",").filter_map { |name| name.strip.presence }.uniq
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

  def merge
    canonical = Genre.find(genre_params[:canonical_genre_id])
    Genre.find(params[:id]).merge_into!(canonical)
    redirect_to return_to
  end

  private

  def genre_params
    params.expect(genre: %i[canonical_genre_id parent_genre_id])
  end

  def return_to
    to = params[:return_to].to_s
    to.start_with?("/") ? to : genres_path
  end

  def load_suggestions
    @alias_suggestions = @genre ? AliasSuggester.call(@genre) : []
    @related_suggestions = @genre ? RelatedGenreSuggester.call(@genre, exclude: @alias_suggestions.map(&:id)) : []
  end

  def sample_events_for(genre)
    return Event.none unless genre

    Event.tagged_with(genre.name, on: :genres).includes(:locations).order(start_date: :desc).limit(5)
  end
end
