class GenresController < ApplicationController
  before_action :require_admin

  STATUS_SCOPES = {
    "unplaced" => :unplaced,
    "placed" => :placed,
    "ignored" => :ignored,
    "hidden" => :hidden,
    "blocked" => :blocked
  }.freeze

  # Browse default is alphabetical (finding a known genre); 'count' surfaces the
  # heaviest hitters (the queue's order).
  SORT_SCOPES = { "name" => :by_name, "count" => :by_usage }.freeze

  # Standard CRUD entry, filterable by status and sortable. Browsing shows the
  # curation catalogue (`Genre.listable` = in use + parked); a name search instead
  # reaches *every* genre — including dormant taxonomy entries and genres you've
  # touched that currently tag 0 events — so nothing is ever truly hidden, it's
  # just one search away.
  def index
    @status = STATUS_SCOPES.key?(params[:status]) ? params[:status] : "all"
    @sort = SORT_SCOPES.key?(params[:sort]) ? params[:sort] : "name"
    scope = @status == "all" ? Genre.all : Genre.public_send(STATUS_SCOPES[@status])
    scope = params[:q].present? ? scope.where("name ILIKE ?", "%#{params[:q]}%") : scope.listable
    @genres = scope.public_send(SORT_SCOPES[@sort]).includes(:parent).page(params[:page]).per(50)
  end

  # Read-only hierarchy view: the curated genre tree, roots → descendants, for
  # eyeballing the cultivation at a glance. Loads the whole placed taxonomy once
  # (dispositions/aliases excluded — they sit outside the tree) and builds the
  # parent→children map in memory, so the recursive render does no per-node query.
  def tree
    genres = Genre.where(hidden_at: nil, blocked_at: nil, ignored_at: nil, canonical_id: nil)
                  .by_name.to_a
    @children = genres.group_by(&:parent_id)
    # A top-level genre is a tree *root* only if something points to it as a
    # parent. This keeps the unplaced genres (parent_id nil, no children — the
    # curation queue's backlog) out of the hierarchy view; they're summarised
    # below and curated from the queue, not here.
    parents = @children.keys.compact.to_set
    @roots = (@children[nil] || []).select { |g| parents.include?(g.id) }
    @placed = Genre.placed.count
    @unplaced = Genre.unplaced.count
  end

  # The curation queue: serve the single highest-impact genre not yet filed into
  # the tree (unplaced = in use, no parent, no disposition), plus alias suggestions
  # and the events it appears on. Placing/ignoring it returns here, surfacing the
  # next one — a "tinder" flow.
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

  # File a genre into the tree under a chosen parent. A blank parent makes it a
  # top-level (root) genre. The
  # combobox emits a single parent genre id. Rejects cycles (self/descendant).
  def set_parent
    Genre.find(params[:id]).set_parent!(genre_params[:parent_genre_id])
    redirect_to return_to
  rescue ArgumentError => e
    redirect_to return_to, alert: e.message
  end

  # Selection chips for the per-event genre-override combobox (admin/events#show).
  # Mirrors StylesController#chips but admin-gated (require_admin above).
  def chips
    @genres = Genre.where(id: params[:combobox_values].to_s.split(",")).distinct.by_name
    render turbo_stream: helpers.combobox_selection_chips_for(@genres)
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
    params.expect(genre: %i[canonical_genre_id parent_genre_id])
  end

  # Where to land after an action. Constrained to internal paths so the
  # round-tripped value can't be turned into an open redirect.
  def return_to
    to = params[:return_to].to_s
    to.start_with?("/") ? to : genres_path
  end

  # The two suggestion rows: tight Levenshtein near-spellings to merge, plus
  # word-overlap "related genres" for filing (tighter parent / merge target).
  # Related excludes anything already shown as an alias so the two never repeat.
  def load_suggestions
    @alias_suggestions = @genre ? AliasSuggester.call(@genre) : []
    @related_suggestions = @genre ? RelatedGenreSuggester.call(@genre, exclude: @alias_suggestions.map(&:id)) : []
  end

  def sample_events_for(genre)
    return Event.none unless genre

    Event.tagged_with(genre.name, on: :genres).includes(:locations).order(start_date: :desc).limit(5)
  end
end
